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
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/s3backend"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/suite"
)

// StagedDeploymentSuite tests the full GCP infrastructure deployment in stages
type StagedDeploymentSuite struct {
	basesuite.BaseTestSuite
	workingDir string
	uniqueId   string
	s3Manager  *s3backend.Manager
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

	test_structure.RunTestStage(t, "cleanup_network", func() {
		// Cleanup network if it was created in this test run
		networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
		if networkOptions := helpers.SafeLoadTerraformOptions(t, networkStageDir); networkOptions != nil {
			t.Logf("🗑️ Cleaning up network...")
			terraform.Destroy(t, networkOptions)
			t.Logf("✅ Network cleanup completed")

			helpers.CleanupTestWorkspace(t, utils.GCP, suite.uniqueId, utils.NetworkingDir)

			// Remove entire state directory since network is the foundation
			t.Logf("🗂️ Removing state directory: %s", suite.workingDir)
			os.RemoveAll(suite.workingDir)
			t.Logf("✅ State directory cleanup completed")
		} else {
			t.Logf("♻️ No network to cleanup (was not created in this test)")
		}
	})

	// S3 backend state files are managed by Terraform and will persist in S3
	// Use S3 lifecycle policies to manage retention if needed

	suite.TearDownBaseSuite()
}

func (suite *StagedDeploymentSuite) testDiskEnabledCleanup() {
	t := suite.T()
	t.Log("🧹 Running testDiskEnabled Cleanup (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "cleanup_testDiskEnabled", func() {
		// Cleanup consolidated Materialize stack
		suite.cleanupStage("cleanup_testDiskEnabled", utils.MaterializeDiskEnabledDir)
	})

	t.Logf("✅ testDiskEnabled Cleanup completed successfully")
}

func (suite *StagedDeploymentSuite) testDiskDisabledCleanup() {
	t := suite.T()
	t.Log("🧹 Running testDiskDisabled Cleanup (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "cleanup_testDiskDisabled", func() {
		// Cleanup consolidated Materialize stack
		suite.cleanupStage("cleanup_testDiskDisabled", utils.MaterializeDiskDisabledDir)
	})

	t.Logf("✅ testDiskDisabled Cleanup completed successfully")
}

func (suite *StagedDeploymentSuite) cleanupStage(stageName, stageDir string) {
	t := suite.T()
	t.Logf("🗑️ Cleaning up %s stage: %s", stageName, stageDir)

	options := helpers.SafeLoadTerraformOptions(t, filepath.Join(suite.workingDir, stageDir))
	if options == nil {
		t.Logf("♻️ No %s stage to cleanup (was not created in this test)", stageName)
		return
	}

	terraform.Destroy(t, options)
	t.Logf("✅ %s stage cleanup completed", stageName)

	// Cleanup workspace
	helpers.CleanupTestWorkspace(t, utils.GCP, suite.uniqueId, stageDir)
}

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → (disk-enabled-setup) → (disk-disabled-setup)
func (suite *StagedDeploymentSuite) TestFullDeployment() {
	t := suite.T()
	projectID := os.Getenv("GOOGLE_PROJECT")

	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		var uniqueId string
		if os.Getenv("USE_EXISTING_NETWORK") != "" {
			// Use existing network and initialize S3 backend
			uniqueId = suite.useExistingNetwork()
		} else {
			// Generate unique ID for new infrastructure
			uniqueId = generateGCPCompliantID()
			suite.workingDir = filepath.Join(dir.GetProjectRootDir(), utils.MainTestDir, utils.GCP, uniqueId)
			os.MkdirAll(suite.workingDir, 0755)
			t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
			t.Logf("📁 Test Stage Output directory: %s", suite.workingDir)

			// Save unique ID for subsequent stages
			test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)
			suite.uniqueId = uniqueId

			// Initialize S3 backend manager for new network
			s3Manager, err := initS3BackendManager(t, uniqueId)
			if err != nil {
				t.Fatalf("❌ Failed to initialize S3 backend manager: %v", err)
			}
			suite.s3Manager = s3Manager
		}

		// Short ID will used as resource name prefix so that we don't exceed the length limit
		shortId := strings.Split(uniqueId, "-")[1]

		// Set up networking fixture
		networkingPath := helpers.SetupTestWorkspace(t, utils.GCP, uniqueId, utils.NetworkingFixture, utils.NetworkingDir)

		// Create terraform.tfvars.json file for network stage
		networkTfvarsPath := filepath.Join(networkingPath, "terraform.tfvars.json")
		networkVariables := map[string]interface{}{
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
		}
		helpers.CreateTfvarsFile(t, networkTfvarsPath, networkVariables)

		networkOptions := &terraform.Options{
			TerraformDir: networkingPath,
			VarFiles:     []string{"terraform.tfvars.json"},
			RetryableTerraformErrors: map[string]string{
				"RequestError": "Request failed",
			},
			MaxRetries:         TestMaxRetries,
			TimeBetweenRetries: TestRetryDelay,
			NoColor:            true,
		}

		// Configure S3 backend if enabled - Terraform will handle state management
		applyBackendConfigToTerraformOptions(networkOptions, suite.s3Manager, utils.NetworkingDir)

		// Save terraform options for potential cleanup stage
		networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
		test_structure.SaveTerraformOptions(t, networkStageDir, networkOptions)

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

		// Save all outputs and resource IDs to networking directory
		test_structure.SaveString(t, networkStageDir, "network_name", networkName)
		test_structure.SaveString(t, networkStageDir, "network_id", networkId)
		test_structure.SaveString(t, networkStageDir, "subnets_names", strings.Join(subnetNames, ","))
		test_structure.SaveString(t, networkStageDir, "subnets_ids", strings.Join(subnetIds, ","))
		test_structure.SaveString(t, networkStageDir, "router_name", routerName)
		test_structure.SaveString(t, networkStageDir, "nat_name", natName)
		test_structure.SaveString(t, networkStageDir, "private_vpc_connection", privateVpcConnection)

		t.Logf("✅ Network infrastructure created:")
		t.Logf("  🌐 Network: %s", networkName)
		t.Logf("  🏠 Subnets: %s", strings.Join(subnetNames, ","))
		t.Logf("  🔀 Router: %s", routerName)
		t.Logf("  🌍 NAT: %s", natName)
		t.Logf("  🏷️ Resource ID: %s", uniqueId)

	})

	// If network stage was skipped, use existing network
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Stage 2: testDiskEnabled (GKE + Database + Materialize)
	suite.testDiskEnabled(projectID)

	// Stage 3: testDiskDisabled (GKE + Database + Materialize)
	suite.testDiskDisabled(projectID)
}

// testDiskEnabled deploys the complete Materialize stack with disk enabled
func (suite *StagedDeploymentSuite) testDiskEnabled(projectID string) {
	t := suite.T()
	t.Log("🚀 Running testDiskEnabled (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "testDiskEnabled", func() {
		suite.setupMaterializeConsolidatedStage("testDiskEnabled", utils.MaterializeDiskEnabledDir,
			projectID, utils.DiskEnabledShortSuffix, true)
	})

	t.Logf("✅ testDiskEnabled completed successfully")
}

// testDiskDisabled deploys the complete Materialize stack with disk disabled
func (suite *StagedDeploymentSuite) testDiskDisabled(projectID string) {
	t := suite.T()
	t.Log("🚀 Running testDiskDisabled (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "testDiskDisabled", func() {
		suite.setupMaterializeConsolidatedStage("testDiskDisabled", utils.MaterializeDiskDisabledDir,
			projectID, utils.DiskDisabledShortSuffix, false)
	})

	t.Logf("✅ testDiskDisabled completed successfully")
}

// setupMaterializeConsolidatedStage deploys the complete Materialize stack (GKE + Materialize)
func (suite *StagedDeploymentSuite) setupMaterializeConsolidatedStage(stage, stageDir, projectID, nameSuffix string, diskEnabled bool) {
	t := suite.T()
	t.Logf("🔧 Setting up consolidated Materialize stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create Materialize stack: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data
	networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
	networkName := test_structure.LoadString(t, networkStageDir, "network_name")
	networkId := test_structure.LoadString(t, networkStageDir, "network_id")
	subnetNamesStr := test_structure.LoadString(t, networkStageDir, "subnets_names")
	subnetNames := strings.Split(subnetNamesStr, ",")

	// Validate required network data exists
	if networkName == "" || networkId == "" || len(subnetNames) == 0 || subnetNames[0] == "" || suite.uniqueId == "" {
		t.Fatal("❌ Cannot create Materialize stack: Missing network data. Run network setup stage first.")
	}

	t.Logf("🔗 Using infrastructure family: %s", suite.uniqueId)

	// Set up consolidated Materialize fixture
	materializePath := helpers.SetupTestWorkspace(t, utils.GCP, suite.uniqueId, utils.MaterializeFixture, stageDir)

	expectedInstanceNamespace := fmt.Sprintf("mz-instance-%s", nameSuffix)
	expectedOperatorNamespace := fmt.Sprintf("mz-operator-%s", nameSuffix)
	expectedCertManagerNamespace := fmt.Sprintf("cert-manager-%s", nameSuffix)
	shortId := strings.Split(suite.uniqueId, "-")[1]
	resourceName := fmt.Sprintf("%s%s", shortId, nameSuffix)

	// Create terraform.tfvars.json file instead of using Vars map
	// This approach is cleaner and follows Terraform best practices
	tfvarsPath := filepath.Join(materializePath, "terraform.tfvars.json")

	// Configure disk settings and machine type based on disk enabled/disabled
	diskSize := TestGKEDiskDisabledDiskSize
	localSSDCount := TestGKEDiskDisabledLocalSSDCount
	machineType := TestGKEDiskDisabledMachineType
	if diskEnabled {
		diskSize = TestGKEDiskEnabledDiskSize
		localSSDCount = TestGKEDiskEnabledLocalSSDCount
		machineType = TestGKEDiskEnabledMachineType
	}

	dbName := TestDBNameDisk
	if !diskEnabled {
		dbName = TestDBNameNoDisk
	}

	// Build variables map for the generic tfvars creation function
	variables := map[string]interface{}{
		// GCP Configuration
		"project_id": projectID,
		"region":     TestRegion,
		"prefix":     resourceName,

		// Network Configuration
		"network_name": networkName,
		"network_id":   networkId,
		"subnet_name":  subnetNames[0],

		// GKE Configuration
		"namespace":             TestGKENamespace,
		"materialize_node_type": machineType,
		"min_nodes":             TestGKEMinNodes,
		"max_nodes":             TestGKEMaxNodes,
		"enable_private_nodes":  true,
		"swap_enabled":          diskEnabled,
		"disk_size":             diskSize,
		"local_ssd_count":       localSSDCount,

		// Node Labels
		"labels": map[string]string{
			"environment":  helpers.GetEnvironment(),
			"project":      utils.ProjectName,
			"test-run":     suite.uniqueId,
			"disk-enabled": strconv.FormatBool(diskEnabled),
		},

		// Database Configuration
		"database_tier": TestDatabaseTier,
		"db_version":    TestDatabaseVersion,
		"databases": []map[string]interface{}{
			{
				"name": dbName,
			},
		},
		"users": []map[string]interface{}{
			{
				"name":     TestDBUsername,
				"password": TestPassword,
			},
		},

		// Storage Configuration
		"storage_bucket_versioning":  TestStorageBucketVersioning,
		"storage_bucket_version_ttl": TestStorageBucketVersionTTL,

		// Cert Manager Configuration
		"cert_manager_install_timeout": TestCertManagerInstallTimeout,
		"cert_manager_chart_version":   TestCertManagerVersion,
		"cert_manager_namespace":       expectedCertManagerNamespace,

		// Operator Configuration
		"operator_namespace": expectedOperatorNamespace,

		// Materialize Instance Configuration
		"instance_name":      TestMaterializeInstanceName,
		"instance_namespace": expectedInstanceNamespace,
		"user": map[string]interface{}{
			"name":     TestDBUsername,
			"password": TestPassword,
		},
		"external_login_password_mz_system": TestPassword,
		"license_key":                       os.Getenv("MATERIALIZE_LICENSE_KEY"),
	}

	helpers.CreateTfvarsFile(t, tfvarsPath, variables)
	materializeOptions := &terraform.Options{
		TerraformDir: materializePath,
		VarFiles:     []string{"terraform.tfvars.json"},
		RetryableTerraformErrors: map[string]string{
			"RequestError": "Request failed",
		},
		MaxRetries:         TestMaxRetries,
		TimeBetweenRetries: TestRetryDelay,
		NoColor:            true,
	}

	// Configure S3 backend if enabled - Terraform will handle state management
	applyBackendConfigToTerraformOptions(materializeOptions, suite.s3Manager, stageDir)

	// Save terraform options for cleanup
	stageDirPath := filepath.Join(suite.workingDir, stageDir)
	test_structure.SaveTerraformOptions(t, stageDirPath, materializeOptions)

	// Apply
	terraform.InitAndApply(t, materializeOptions)

	// Validate all outputs from the consolidated fixture
	t.Log("🔍 Validating all consolidated fixture outputs...")

	// GKE Cluster Outputs
	clusterName := terraform.Output(t, materializeOptions, "cluster_name")
	clusterEndpoint := terraform.Output(t, materializeOptions, "cluster_endpoint")
	clusterCA := terraform.Output(t, materializeOptions, "cluster_ca_certificate")
	workloadIdentitySA := terraform.Output(t, materializeOptions, "workload_identity_sa_email")

	// Database Outputs
	dbInstanceName := terraform.Output(t, materializeOptions, "instance_name")
	privateIP := terraform.Output(t, materializeOptions, "private_ip")

	// Materialize Instance Outputs
	instanceResourceId := terraform.Output(t, materializeOptions, "instance_resource_id")

	// Comprehensive validation
	t.Log("✅ Validating GKE Cluster Outputs...")
	suite.NotEmpty(clusterName, "GKE cluster name should not be empty")
	suite.NotEmpty(clusterEndpoint, "GKE cluster endpoint should not be empty")
	suite.NotEmpty(clusterCA, "GKE cluster CA certificate should not be empty")
	suite.NotEmpty(workloadIdentitySA, "Workload identity SA email should not be empty")

	t.Log("✅ Validating Database Outputs...")
	suite.NotEmpty(dbInstanceName, "Database instance name should not be empty")
	suite.NotEmpty(privateIP, "Database private IP should not be empty")

	t.Log("✅ Validating Materialize Instance Outputs...")
	suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")

	t.Logf("✅ Complete Materialize stack created successfully:")
	t.Logf("  💾 Disk Enabled: %t", diskEnabled)

	// GKE Cluster Outputs
	t.Logf("🔧 GKE CLUSTER OUTPUTS:")
	t.Logf("  📛 Cluster Name: %s", clusterName)
	t.Logf("  🔗 Cluster Endpoint: %s", clusterEndpoint)
	t.Logf("  🔐 Cluster CA Certificate: [REDACTED]")
	t.Logf("  🆔 Workload Identity SA: %s", workloadIdentitySA)

	// Database Outputs
	t.Logf("🗄️ DATABASE OUTPUTS:")
	t.Logf("  🔗 Instance Name: %s", dbInstanceName)
	t.Logf("  🔗 Private IP: %s", privateIP)

	// Materialize Instance Outputs
	t.Logf("🚀 MATERIALIZE INSTANCE OUTPUTS:")
	t.Logf("  🆔 Instance Resource ID: %s", instanceResourceId)
	t.Logf("  📜 Cert Manager Namespace: %s", expectedCertManagerNamespace)
	t.Logf("  🎛️ Operator Namespace: %s", expectedOperatorNamespace)
	t.Logf("  🏠 Instance Namespace: %s", expectedInstanceNamespace)
}

func (suite *StagedDeploymentSuite) useExistingNetwork() string {
	t := suite.T()
	// Get the most recent state directory
	testCloudDir := filepath.Join(dir.GetProjectRootDir(), utils.MainTestDir, utils.GCP)
	latestDirPath, err := dir.GetLastRunTestStageDir(testCloudDir)
	if err != nil {
		t.Fatalf("❌ Cannot skip network creation: %v", err)
	}

	// Use the full path returned by the helper
	suite.workingDir = latestDirPath

	// Load and return the unique ID
	uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
	if uniqueId == "" {
		t.Fatal("❌ Cannot use existing network: Unique ID not found. Run network setup stage first.")
	}
	suite.uniqueId = uniqueId

	// Validate that network was created successfully by checking network name
	networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
	networkName := test_structure.LoadString(t, networkStageDir, "network_name")
	latestDir := filepath.Base(latestDirPath)
	if networkName == "" {
		t.Fatalf("❌ Cannot skip network creation: Network name is empty in state directory %s", latestDir)
	}

	// Initialize S3 backend manager for existing network
	s3Manager, err := initS3BackendManager(t, uniqueId)
	if err != nil {
		t.Fatalf("❌ Failed to initialize S3 backend manager: %v", err)
	}
	suite.s3Manager = s3Manager

	t.Logf("♻️ Using existing network from: %s (ID: %s, Network: %s)", suite.workingDir, uniqueId, networkName)
	return uniqueId
}

// TestStagedDeploymentSuite runs the staged deployment test suite
func TestStagedDeploymentSuite(t *testing.T) {
	// Run the test suite
	suite.Run(t, new(StagedDeploymentSuite))
}
