package test

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/basesuite"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/config"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/dir"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/suite"
)

// StagedDeploymentSuite tests the full GCP infrastructure deployment in stages
type StagedDeploymentSuite struct {
	basesuite.BaseTestSuite
	workingDir string
}

// SetupSuite initializes the test suite
func (suite *StagedDeploymentSuite) SetupSuite() {
	configurations := config.GetCommonConfigurations()
	configurations = append(configurations, getRequiredGCPConfigurations()...)
	suite.SetupBaseSuite("GCP Staged Deployment", utils.GCP, configurations)
	// Working directory will be set dynamically based on uniqueId
	suite.workingDir = "" // Will be set in network stage
}

// TearDownSuite cleans up the test suite
func (suite *StagedDeploymentSuite) TearDownSuite() {
	t := suite.T()
	t.Logf("🧹 Starting cleanup stages for: %s", suite.SuiteName)
	suite.testDiskDisabledCleanup()

	suite.testDiskEnabledCleanup()

	test_structure.RunTestStage(t, "cleanup_database", func() {
		suite.cleanupStage("cleanup_database", utils.DataBaseDir)
	})

	test_structure.RunTestStage(t, "cleanup_network", func() {
		// Cleanup network if it was created in this test run
		if networkOptions := test_structure.LoadTerraformOptions(t, suite.workingDir); networkOptions != nil {
			t.Logf("🗑️ Cleaning up network...")
			terraform.Destroy(t, networkOptions)
			t.Logf("✅ Network cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.GCP, uniqueId, utils.NetworkingDir)

			// Remove entire state directory since network is the foundation
			t.Logf("🗂️ Removing state directory: %s", suite.workingDir)
			os.RemoveAll(suite.workingDir)
			t.Logf("✅ State directory cleanup completed")
		} else {
			t.Logf("♻️ No network to cleanup (was not created in this test)")
		}
	})
	suite.TearDownBaseSuite()
}

func (suite *StagedDeploymentSuite) testDiskEnabledCleanup() {
	t := suite.T()
	t.Log("Running Disk Enabled Cleanup Tests")

	test_structure.RunTestStage(t, "cleanup_materialize_disk_enabled", func() {
		suite.cleanupStage("cleanup_materialize_disk_enabled", utils.MaterializeDiskEnabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_gke_disk_enabled", func() {
		suite.cleanupStage("cleanup_gke_disk_enabled", utils.GKEDiskEnabledDir)
	})

	t.Logf("✅ Disk Enabled Cleanup completed successfully")
}

func (suite *StagedDeploymentSuite) testDiskDisabledCleanup() {
	t := suite.T()
	t.Log("Running Disk Disabled Cleanup Tests")

	test_structure.RunTestStage(t, "cleanup_materialize_disk_disabled", func() {
		suite.cleanupStage("cleanup_materialize_disk_disabled", utils.MaterializeDiskDisabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_gke_disk_disabled", func() {
		suite.cleanupStage("cleanup_gke_disk_disabled", utils.GKEDiskDisabledDir)
	})

	t.Logf("✅ Disk Disabled Cleanup completed successfully")
}

func (suite *StagedDeploymentSuite) cleanupStage(stageName, stageDir string) {
	t := suite.T()
	t.Logf("🗑️ Cleaning up %s stage: %s", stageName, stageDir)

	options := test_structure.LoadTerraformOptions(t, filepath.Join(suite.workingDir, stageDir))
	if options == nil {
		t.Logf("♻️ No %s stage to cleanup (was not created in this test)", stageName)
		return
	}

	terraform.Destroy(t, options)
	t.Logf("✅ %s stage cleanup completed", stageName)

	// Cleanup workspace
	uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
	helpers.CleanupTestWorkspace(t, utils.GCP, uniqueId, stageDir)
}

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → Database → (disk-enabled-setup) → (disk-disabled-setup)
func (suite *StagedDeploymentSuite) TestFullDeployment() {
	t := suite.T()
	projectID := os.Getenv("GOOGLE_PROJECT")

	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		// Generate unique ID for this infrastructure family
		var uniqueId string
		if os.Getenv("USE_EXISTING_NETWORK") != "" {
			suite.useExistingNetwork()
			uniqueId = test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			if uniqueId == "" {
				t.Fatal("❌ Cannot use existing network: Unique ID not found. Run network setup stage first.")
			}
		} else {
			uniqueId = generateGCPCompliantID()
			suite.workingDir = fmt.Sprintf("%s/%s", TestRunsDir, uniqueId)
			os.MkdirAll(suite.workingDir, 0755)
			t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
			t.Logf("📁 Test Stage Output directory: %s", suite.workingDir)
			// Save unique ID for subsequent stages
			test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)
		}
		// Short ID will used as resource name prefix so that we don't exceed the length limit
		shortId := strings.Split(uniqueId, "-")[1]

		// Set up networking example
		networkingPath := helpers.SetupTestWorkspace(t, utils.GCP, uniqueId, utils.NetworkingDir, utils.NetworkingDir)

		networkOptions := &terraform.Options{
			TerraformDir: networkingPath,
			Vars: map[string]interface{}{
				"project_id": projectID,
				"region":     TestRegion,
				"prefix":     shortId,
				"labels": map[string]string{
					"environment": helpers.GetEnvironment(),
					"project":     utils.ProjectName,
					"test-run":    uniqueId,
				},
				"subnets": []map[string]interface{}{
					{
						"name":           fmt.Sprintf("%s-subnet", shortId),
						"cidr":           TestSubnetCIDR,
						"region":         TestRegion,
						"private_access": true,
						"secondary_ranges": []map[string]interface{}{
							{
								"range_name":    "pods",
								"ip_cidr_range": TestPodsCIDR,
							},
							{
								"range_name":    "services",
								"ip_cidr_range": TestServicesCIDR,
							},
						},
					},
				},
			},
			RetryableTerraformErrors: map[string]string{
				"RequestError": "Request failed",
			},
			MaxRetries:         TestMaxRetries,
			TimeBetweenRetries: TestRetryDelay,
			NoColor:            true,
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, suite.workingDir, networkOptions)

		// Apply
		terraform.InitAndApply(t, networkOptions)

		// Save all networking outputs for subsequent stages
		networkName := terraform.Output(t, networkOptions, "network_name")
		networkId := terraform.Output(t, networkOptions, "network_id")
		subnetNames := terraform.OutputList(t, networkOptions, "subnets_names")
		subnetIds := terraform.OutputList(t, networkOptions, "subnets_ids")
		routerName := terraform.Output(t, networkOptions, "router_name")
		natName := terraform.Output(t, networkOptions, "nat_name")
		privateVpcConnection := terraform.Output(t, networkOptions, "private_vpc_connection")

		// Save all outputs and resource IDs
		test_structure.SaveString(t, suite.workingDir, "network_name", networkName)
		test_structure.SaveString(t, suite.workingDir, "network_id", networkId)
		test_structure.SaveString(t, suite.workingDir, "subnets_names", strings.Join(subnetNames, ","))
		test_structure.SaveString(t, suite.workingDir, "subnets_ids", strings.Join(subnetIds, ","))
		test_structure.SaveString(t, suite.workingDir, "router_name", routerName)
		test_structure.SaveString(t, suite.workingDir, "nat_name", natName)
		test_structure.SaveString(t, suite.workingDir, "private_vpc_connection", privateVpcConnection)

		t.Logf("✅ Network infrastructure created:")
		t.Logf("  🌐 Network: %s", networkName)
		t.Logf("  🏠 Subnets: %s", strings.Join(subnetNames, ","))
		t.Logf("  🔀 Router: %s", routerName)
		t.Logf("  🌍 NAT: %s", natName)
		t.Logf("  🏷️ Resource ID: %s", uniqueId)

	})
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Stage 2: Database Setup
	test_structure.RunTestStage(t, "setup_database", func() {
		suite.setupDatabaseStage("setup_database", utils.DataBaseDir, projectID)
	})

	// Test Disk Enabled Setup
	suite.testDiskEnabledSetup(projectID)

	// Test Disk Disabled Setup
	suite.testDiskDisabledSetup(projectID)
}

func (suite *StagedDeploymentSuite) testDiskEnabledSetup(projectID string) {
	t := suite.T()
	t.Log("Running Disk Enabled Setup Tests")

	// Stage 2: GKE Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_gke_disk_enabled", func() {
		suite.setupGKEStage("setup_gke_disk_enabled", utils.GKEDiskEnabledDir, projectID,
			utils.DiskEnabledShortSuffix, true)
	})

	// Stage 3: Materialize Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_materialize_disk_enabled", func() {
		suite.setupMaterializeStage("setup_materialize_disk_enabled", utils.MaterializeDiskEnabledDir, projectID,
			utils.DiskEnabledShortSuffix, true)
	})
	t.Logf("✅ Disk Enabled Setup completed successfully")
}

func (suite *StagedDeploymentSuite) testDiskDisabledSetup(projectID string) {
	t := suite.T()
	t.Log("Running Disk Disabled Setup Tests")

	test_structure.RunTestStage(t, "setup_gke_disk_disabled", func() {
		suite.setupGKEStage("setup_gke_disk_disabled", utils.GKEDiskDisabledDir, projectID,
			utils.DiskDisabledShortSuffix, false)
	})

	test_structure.RunTestStage(t, "setup_materialize_disk_disabled", func() {
		suite.setupMaterializeStage("setup_materialize_disk_disabled", utils.MaterializeDiskDisabledDir, projectID,
			utils.DiskDisabledShortSuffix, false)
	})
	t.Logf("✅ Disk Disabled Setup completed successfully")
}

func (suite *StagedDeploymentSuite) setupDatabaseStage(stage, stageDir, projectID string) {
	t := suite.T()
	t.Logf("🔧 Setting up Database stage: %s", stage)

	// Ensure workingDir is set (should be set by network stage)
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create database: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data with validation
	networkId := test_structure.LoadString(t, suite.workingDir, "network_id")
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

	// Validate required network data exists
	if networkId == "" || resourceId == "" {
		t.Fatal("❌ Cannot create database: Missing network data. Run network setup stage first.")
	}

	t.Logf("🔗 Using infrastructure family: %s", resourceId)
	// Short ID will used as resource name prefix so that we don't exceed the length limit
	shortId := strings.Split(resourceId, "-")[1]

	// Set up database example
	databasePath := helpers.SetupTestWorkspace(t, utils.GCP, resourceId, utils.DataBaseDir, stageDir)

	dbOptions := &terraform.Options{
		TerraformDir: databasePath,
		Vars: map[string]interface{}{
			"project_id":    projectID,
			"region":        TestRegion,
			"prefix":        shortId,
			"network_id":    networkId,
			"database_tier": TestDatabaseTier,
			"db_version":    TestDatabaseVersion,
			"labels": map[string]string{
				"environment": helpers.GetEnvironment(),
				"project":     utils.ProjectName,
				"test-run":    resourceId,
			},
			"databases": []map[string]interface{}{
				{
					"name": TestDBNameDisk,
				},
				{
					"name": TestDBNameNoDisk,
				},
			},
			"users": []map[string]interface{}{
				{
					"name":     TestDBUsername1,
					"password": TestPassword,
				},
				{
					"name":     TestDBUsername2,
					"password": TestPassword,
				},
			},
		},
		RetryableTerraformErrors: map[string]string{
			"RequestError": "Request failed",
		},
		MaxRetries:         TestMaxRetries,
		TimeBetweenRetries: TestRetryDelay,
		NoColor:            true,
	}

	// Save terraform options for potential cleanup stage
	stageDirPath := filepath.Join(suite.workingDir, stageDir)
	test_structure.SaveTerraformOptions(t, stageDirPath, dbOptions)

	// Apply
	terraform.InitAndApply(t, dbOptions)

	// Validate all database outputs
	dbInstanceName := terraform.Output(t, dbOptions, "instance_name")
	privateIP := terraform.Output(t, dbOptions, "private_ip")

	// Comprehensive validation
	suite.NotEmpty(dbInstanceName, "Database instance name should not be empty")
	suite.NotEmpty(privateIP, "Database private IP should not be empty")

	// Save database outputs for future stages
	test_structure.SaveString(t, stageDirPath, "instance_name", dbInstanceName)
	test_structure.SaveString(t, stageDirPath, "private_ip", privateIP)

	t.Logf("✅ Database created successfully:")
	t.Logf("  🔗 Instance Name: %s", dbInstanceName)
	t.Logf("  🔗 Private IP: %s", privateIP)
}

func (suite *StagedDeploymentSuite) setupGKEStage(stage, stageDir, projectID, nameSuffix string, diskEnabled bool) {
	t := suite.T()
	t.Logf("🔧 Setting up GKE stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create GKE: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data
	networkName := test_structure.LoadString(t, suite.workingDir, "network_name")
	subnetNamesStr := test_structure.LoadString(t, suite.workingDir, "subnets_names")
	subnetNames := strings.Split(subnetNamesStr, ",")
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

	// Validate required network data exists
	if networkName == "" || len(subnetNames) == 0 || resourceId == "" {
		t.Fatal("❌ Cannot create GKE: Missing network data. Run network setup stage first.")
	}
	subnetName := subnetNames[0]

	t.Logf("🔗 Using infrastructure family: %s for GKE (disk-enabled: %t)", resourceId, diskEnabled)
	// Short ID will used as resource name prefix so that we don't exceed the length limit
	shortId := strings.Split(resourceId, "-")[1]

	// Set up GKE example
	gkePath := helpers.SetupTestWorkspace(t, utils.GCP, resourceId, utils.GKEDir, stageDir)

	// Configure disk settings and machine type based on disk enabled/disabled
	diskSize := TestGKEDiskDisabledDiskSize
	localSSDCount := TestGKEDiskDisabledLocalSSDCount
	machineType := TestGKEDiskDisabledMachineType
	if diskEnabled {
		diskSize = TestGKEDiskEnabledDiskSize
		localSSDCount = TestGKEDiskEnabledLocalSSDCount
		machineType = TestGKEDiskEnabledMachineType
	}

	gkeOptions := &terraform.Options{
		TerraformDir: gkePath,
		Vars: map[string]interface{}{
			"project_id":   projectID,
			"region":       TestRegion,
			"prefix":       fmt.Sprintf("%s%s", shortId, nameSuffix),
			"network_name": networkName,
			"subnet_name":  subnetName,
			// the namespace where orchestord will run. i.e where operator is installed.
			// change this later.
			"namespace":             TestGKENamespace,
			"skip_nodepool":         false,
			"materialize_node_type": machineType,
			"labels": map[string]string{
				"environment":  helpers.GetEnvironment(),
				"project":      utils.ProjectName,
				"test-run":     resourceId,
				"disk-enabled": strconv.FormatBool(diskEnabled),
			},
			"min_nodes":            TestGKEMinNodes,
			"max_nodes":            TestGKEMaxNodes,
			"enable_private_nodes": true,
			"swap_enabled":         diskEnabled,
			"disk_size":            diskSize,
			"local_ssd_count":      localSSDCount,
		},
		RetryableTerraformErrors: map[string]string{
			"RequestError": "Request failed",
		},
		MaxRetries:         TestMaxRetries,
		TimeBetweenRetries: TestRetryDelay,
		NoColor:            true,
	}

	// Save terraform options for potential cleanup stage
	stageDirPath := filepath.Join(suite.workingDir, stageDir)
	test_structure.SaveTerraformOptions(t, stageDirPath, gkeOptions)

	// Apply
	terraform.InitAndApply(t, gkeOptions)

	// Save GKE outputs for subsequent stages
	clusterName := terraform.Output(t, gkeOptions, "cluster_name")
	clusterEndpoint := terraform.Output(t, gkeOptions, "cluster_endpoint")
	clusterCA := terraform.Output(t, gkeOptions, "cluster_ca_certificate")
	workloadIdentitySA := terraform.Output(t, gkeOptions, "workload_identity_sa_email")

	// Validate outputs
	suite.NotEmpty(clusterName, "GKE cluster name should not be empty")
	suite.NotEmpty(clusterEndpoint, "GKE cluster endpoint should not be empty")
	suite.NotEmpty(clusterCA, "GKE cluster CA certificate should not be empty")
	suite.NotEmpty(workloadIdentitySA, "Workload identity SA email should not be empty")

	// Save all outputs
	test_structure.SaveString(t, stageDirPath, "cluster_name", clusterName)
	test_structure.SaveString(t, stageDirPath, "cluster_endpoint", clusterEndpoint)
	test_structure.SaveString(t, stageDirPath, "cluster_ca_certificate", clusterCA)
	test_structure.SaveString(t, stageDirPath, "workload_identity_sa_email", workloadIdentitySA)

	t.Logf("✅ GKE cluster (disk-enabled: %t) created successfully:", diskEnabled)
	t.Logf("  📛 Cluster Name: %s", clusterName)
	t.Logf("  🔗 Endpoint: %s", clusterEndpoint)
	t.Logf("  🆔 Workload Identity SA: %s", workloadIdentitySA)
	t.Logf("  💾 Disk Enabled: %t", diskEnabled)
}

func (suite *StagedDeploymentSuite) setupMaterializeStage(stage, stageDir, projectID, nameSuffix string, diskEnabled bool) {
	t := suite.T()
	t.Logf("🔧 Setting up Materialize stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create Materialize: Working directory not set. Run network setup stage first.")
	}

	gkeStageDir := utils.GKEDiskDisabledDir
	if diskEnabled {
		gkeStageDir = utils.GKEDiskEnabledDir
	}
	gkeStageDirFullPath := filepath.Join(suite.workingDir, gkeStageDir)

	// Load saved GKE cluster data
	clusterEndpoint := test_structure.LoadString(t, gkeStageDirFullPath, "cluster_endpoint")
	clusterCA := test_structure.LoadString(t, gkeStageDirFullPath, "cluster_ca_certificate")
	workloadIdentitySA := test_structure.LoadString(t, gkeStageDirFullPath, "workload_identity_sa_email")
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

	if clusterEndpoint == "" || clusterCA == "" || workloadIdentitySA == "" {
		t.Fatal("❌ Cannot create Materialize: Missing GKE cluster data. Run GKE setup stage first.")
	}

	databaseStageDirFullPath := filepath.Join(suite.workingDir, utils.DataBaseDir)
	// Load database details
	databaseHost := test_structure.LoadString(t, databaseStageDirFullPath, "private_ip")

	if databaseHost == "" {
		t.Fatal("❌ Cannot create Materialize: Missing database details. Run database setup stage first.")
	}

	t.Logf("🔗 Using GKE cluster where disk-enabled: %t", diskEnabled)
	// Short ID will used as resource name prefix so that we don't exceed the length limit
	shortId := strings.Split(resourceId, "-")[1]

	// Set up Materialize example
	materializePath := helpers.SetupTestWorkspace(t, utils.GCP, resourceId, utils.MaterializeDir, stageDir)

	databaseName := TestDBNameNoDisk
	username := TestDBUsername2
	if diskEnabled {
		databaseName = TestDBNameDisk
		username = TestDBUsername1
	}

	// Create namespaces using the same pattern as Azure
	expectedInstanceNamespace := fmt.Sprintf("mz-instance-%s", nameSuffix)
	expectedOperatorNamespace := fmt.Sprintf("mz-operator-%s", nameSuffix)
	expectedCertManagerNamespace := fmt.Sprintf("cert-manager-%s", nameSuffix)

	materializeOptions := &terraform.Options{
		TerraformDir: materializePath,
		Vars: map[string]interface{}{
			// Basic configuration
			"project_id": projectID,
			"region":     TestRegion,
			"prefix":     fmt.Sprintf("%s%s", shortId, nameSuffix),
			"labels": map[string]string{
				"environment":  helpers.GetEnvironment(),
				"project":      utils.ProjectName,
				"test-run":     resourceId,
				"disk-enabled": strconv.FormatBool(diskEnabled),
			},

			// Cluster configuration
			"cluster_ca_certificate":     clusterCA,
			"cluster_endpoint":           clusterEndpoint,
			"workload_identity_sa_email": workloadIdentitySA,

			// Storage configuration
			"storage_bucket_versioning":  TestStorageBucketVersioning,
			"storage_bucket_version_ttl": TestStorageBucketVersionTTL,

			// Certificate manager configuration
			"install_cert_manager":         true,
			"cert_manager_install_timeout": TestCertManagerInstallTimeout,
			"cert_manager_chart_version":   TestCertManagerVersion,
			"cert_manager_namespace":       expectedCertManagerNamespace,

			// Disk setup configuration
			"swap_enabled": diskEnabled,

			// Materialize operator configuration
			"operator_namespace": expectedOperatorNamespace,

			// Materialize instance configuration
			"install_materialize_instance": false, // Phase 1: operator only
			"instance_name":                TestMaterializeInstanceName,
			"instance_namespace":           expectedInstanceNamespace,

			// Database configuration
			"database_host": databaseHost,
			"database_name": databaseName,
			"user": map[string]interface{}{
				"name":     username,
				"password": TestPassword,
			},

			// Authentication
			"external_login_password": TestPassword,
			"license_key":             os.Getenv("MATERIALIZE_LICENSE_KEY"),
		},
		RetryableTerraformErrors: map[string]string{
			"RequestError": "Request failed",
		},
		MaxRetries:         TestMaxRetries,
		TimeBetweenRetries: TestRetryDelay,
		NoColor:            true,
	}

	// Save terraform options for potential cleanup stage
	stageDirFullPath := filepath.Join(suite.workingDir, stageDir)
	test_structure.SaveTerraformOptions(t, stageDirFullPath, materializeOptions)

	// Apply
	terraform.InitAndApply(t, materializeOptions)

	t.Logf("✅ Phase 1: Materialize operator installed on cluster where disk-enabled: %t", diskEnabled)

	// Phase 2: Update variables for instance deployment
	materializeOptions.Vars["install_materialize_instance"] = true

	// Phase 2: Apply with instance enabled
	terraform.Apply(t, materializeOptions)

	// Save Materialize outputs for subsequent stages
	instanceResourceId := terraform.Output(t, materializeOptions, "instance_resource_id")

	suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")

	test_structure.SaveString(t, stageDirFullPath, "instance_resource_id", instanceResourceId)

	t.Logf("✅ Phase 2: Materialize instance created successfully:")
	t.Logf("  🗄️ Instance Resource ID: %s", instanceResourceId)
	t.Logf("  💾 Disk Enabled: %t", diskEnabled)
	t.Logf("  📜 Cert Manager Namespace: %s", expectedCertManagerNamespace)
	t.Logf("  🎛️ Operator Namespace: %s", expectedOperatorNamespace)
	t.Logf("  🏠 Instance Namespace: %s", expectedInstanceNamespace)
}

func (suite *StagedDeploymentSuite) useExistingNetwork() {
	t := suite.T()
	// Get the most recent state directory
	latestDirPath, err := dir.GetLastRunTestStageDir(TestRunsDir)
	if err != nil {
		t.Fatalf("❌ Cannot skip network creation: %v", err)
	}

	// Use the full path returned by the helper
	suite.workingDir = latestDirPath
	latestDir := filepath.Base(latestDirPath)

	// Load network name using test_structure (handles .test-data path internally)
	networkName := test_structure.LoadString(t, suite.workingDir, "network_name")
	if networkName == "" {
		t.Fatalf("❌ Cannot skip network creation: Network name is empty in state directory %s", latestDir)
	}

	t.Logf("♻️ Skipping network creation, using existing: %s (ID: %s)", networkName, latestDir)
}

// TestStagedDeploymentSuite runs the staged deployment test suite
func TestStagedDeploymentSuite(t *testing.T) {
	// Run the test suite
	suite.Run(t, new(StagedDeploymentSuite))
}
