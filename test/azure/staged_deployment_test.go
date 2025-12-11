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

// StagedDeploymentSuite tests the full Azure infrastructure deployment in stages
type StagedDeploymentSuite struct {
	basesuite.BaseTestSuite
	workingDir string
	uniqueId   string
	s3Manager  *s3backend.Manager
}

// SetupSuite initializes the test suite
func (suite *StagedDeploymentSuite) SetupSuite() {
	configurations := config.GetCommonConfigurations()
	configurations = append(configurations, getRequiredAzureConfigurations()...)
	suite.SetupBaseSuite("Azure Staged Deployment", utils.Azure, configurations)
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

			helpers.CleanupTestWorkspace(t, utils.Azure, suite.uniqueId, utils.NetworkingDir)

			// Remove entire state directory since network is the foundation
			t.Logf("🗂️ Removing state directory: %s", suite.workingDir)
			os.RemoveAll(suite.workingDir)
			t.Logf("✅ State directory cleanup completed")
			// Clean up S3 uploaded files (tfvars/tfstate) for this test run after local cleanup is complete
			if suite.s3Manager != nil {
				if err := suite.s3Manager.CleanupTestRun(t); err != nil {
					t.Logf("⚠️ Failed to cleanup S3 files (non-fatal): %v", err)
				}
				t.Logf("✅ S3 files cleanup completed")
			}
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
	helpers.CleanupTestWorkspace(t, utils.Azure, suite.uniqueId, stageDir)
}

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → (disk-enabled-setup) → (disk-disabled-setup)
func (suite *StagedDeploymentSuite) TestFullDeployment() {
	t := suite.T()
	subscriptionID := os.Getenv("AZURE_SUBSCRIPTION_ID")
	testRegion := os.Getenv("TEST_REGION")
	if testRegion == "" {
		testRegion = TestRegion
	}

	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		var uniqueId string
		if os.Getenv("USE_EXISTING_NETWORK") != "" {
			// Use existing network and initialize S3 backend
			uniqueId = suite.useExistingNetwork()
		} else {
			// Generate unique ID for new infrastructure
			uniqueId = generateAzureCompliantID()
			suite.workingDir = filepath.Join(dir.GetProjectRootDir(), utils.MainTestDir, utils.Azure, uniqueId)
			os.MkdirAll(suite.workingDir, 0755)
			t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
			t.Logf("📁 Test Stage Output directory: %s", suite.workingDir)

			// Save unique ID for subsequent stages
			test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)
			suite.uniqueId = uniqueId

			// Initialize S3 backend manager for new network
			s3Manager, err := s3backend.InitManager(t, utils.Azure, uniqueId)
			if err != nil {
				t.Fatalf("❌ Failed to initialize S3 backend manager: %v", err)
			}
			suite.s3Manager = s3Manager
		}

		// Short ID will used as resource name prefix so that we don't exceed the length limit
		shortId := strings.Split(uniqueId, "-")[1]
		// Set up networking fixture
		networkingPath := helpers.SetupTestWorkspace(t, utils.Azure, uniqueId, utils.NetworkingFixture, utils.NetworkingDir)

		// Create terraform.tfvars.json file for network stage
		networkTfvarsPath := filepath.Join(networkingPath, "terraform.tfvars.json")
		networkVariables := map[string]interface{}{
			"subscription_id":      subscriptionID,
			"resource_group_name":  fmt.Sprintf("%s-rg", shortId),
			"location":             testRegion,
			"prefix":               shortId,
			"vnet_address_space":   TestVNetAddressSpace,
			"aks_subnet_cidr":      TestAKSSubnetCIDR,
			"postgres_subnet_cidr": TestPostgresSubnetCIDR,
			"tags": map[string]string{
				"environment": helpers.GetEnvironment(),
				"project":     utils.ProjectName,
				"test-run":    uniqueId,
			},
		}
		helpers.CreateTfvarsFile(t, networkTfvarsPath, networkVariables)

		// Upload tfvars to S3 for debugging/cleanup scenarios
		if err := suite.s3Manager.UploadTfvars(t, utils.NetworkingDir, networkTfvarsPath); err != nil {
			t.Logf("⚠️ Failed to upload tfvars to S3 (non-fatal): %v", err)
		}

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
		networkOptions.BackendConfig = suite.s3Manager.GetBackendConfig(utils.NetworkingDir)

		// Save terraform options for potential cleanup stage
		networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
		test_structure.SaveTerraformOptions(t, networkStageDir, networkOptions)

		// Apply
		terraform.InitAndApply(t, networkOptions)

		// Save all networking outputs for subsequent stages
		resourceGroupName := terraform.Output(t, networkOptions, "resource_group_name")
		vnetId := terraform.Output(t, networkOptions, "vnet_id")
		vnetName := terraform.Output(t, networkOptions, "vnet_name")
		aksSubnetId := terraform.Output(t, networkOptions, "aks_subnet_id")
		aksSubnetName := terraform.Output(t, networkOptions, "aks_subnet_name")
		postgresSubnetId := terraform.Output(t, networkOptions, "postgres_subnet_id")
		privateDNSZoneId := terraform.Output(t, networkOptions, "private_dns_zone_id")

		// Save all outputs and resource IDs to networking directory
		test_structure.SaveString(t, networkStageDir, "resource_group_name", resourceGroupName)
		test_structure.SaveString(t, networkStageDir, "vnet_id", vnetId)
		test_structure.SaveString(t, networkStageDir, "vnet_name", vnetName)
		test_structure.SaveString(t, networkStageDir, "aks_subnet_id", aksSubnetId)
		test_structure.SaveString(t, networkStageDir, "aks_subnet_name", aksSubnetName)
		test_structure.SaveString(t, networkStageDir, "postgres_subnet_id", postgresSubnetId)
		test_structure.SaveString(t, networkStageDir, "private_dns_zone_id", privateDNSZoneId)
		test_structure.SaveString(t, suite.workingDir, "test_region", testRegion)

		t.Logf("✅ Network infrastructure created:")
		t.Logf("  🏠 Resource Group: %s", resourceGroupName)
		t.Logf("  🌐 VNet: %s (%s)", vnetName, vnetId)
		t.Logf("  🏠 AKS Subnet: %s", aksSubnetName)
		t.Logf("  🏷️ Resource ID: %s", uniqueId)

	})

	// If network stage was skipped, use existing network
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Stage 2: testDiskEnabled (AKS + Database + Materialize)
	suite.testDiskEnabled(subscriptionID, testRegion)

	// Stage 3: testDiskDisabled (AKS + Database + Materialize)
	suite.testDiskDisabled(subscriptionID, testRegion)
}

// testDiskEnabled deploys the complete Materialize stack with disk enabled
func (suite *StagedDeploymentSuite) testDiskEnabled(subscriptionID, testRegion string) {
	t := suite.T()
	t.Log("🚀 Running testDiskEnabled (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "testDiskEnabled", func() {
		suite.setupMaterializeConsolidatedStage("testDiskEnabled", utils.MaterializeDiskEnabledDir,
			subscriptionID, testRegion, utils.DiskEnabledShortSuffix, true, TestAKSDiskEnabledVMSize)
	})

	t.Logf("✅ testDiskEnabled completed successfully")
}

// testDiskDisabled deploys the complete Materialize stack with disk disabled
func (suite *StagedDeploymentSuite) testDiskDisabled(subscriptionID, testRegion string) {
	t := suite.T()
	t.Log("🚀 Running testDiskDisabled (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "testDiskDisabled", func() {
		suite.setupMaterializeConsolidatedStage("testDiskDisabled", utils.MaterializeDiskDisabledDir,
			subscriptionID, testRegion, utils.DiskDisabledShortSuffix, false, TestAKSDiskDisabledVMSize)
	})

	t.Logf("✅ testDiskDisabled completed successfully")
}

// setupMaterializeConsolidatedStage deploys the complete Materialize stack (AKS + Database + Materialize)
func (suite *StagedDeploymentSuite) setupMaterializeConsolidatedStage(stage, stageDir, subscriptionID, region, nameSuffix string, diskEnabled bool, vmSize string) {
	t := suite.T()
	t.Logf("🔧 Setting up consolidated Materialize stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create Materialize stack: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data
	networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
	resourceGroupName := test_structure.LoadString(t, networkStageDir, "resource_group_name")
	vnetName := test_structure.LoadString(t, networkStageDir, "vnet_name")
	aksSubnetId := test_structure.LoadString(t, networkStageDir, "aks_subnet_id")
	aksSubnetName := test_structure.LoadString(t, networkStageDir, "aks_subnet_name")
	postgresSubnetId := test_structure.LoadString(t, networkStageDir, "postgres_subnet_id")
	privateDNSZoneId := test_structure.LoadString(t, networkStageDir, "private_dns_zone_id")

	// Validate required network data exists
	if resourceGroupName == "" || vnetName == "" || aksSubnetId == "" || postgresSubnetId == "" || privateDNSZoneId == "" || suite.uniqueId == "" {
		t.Fatal("❌ Cannot create Materialize stack: Missing network data. Run network setup stage first.")
	}

	t.Logf("🔗 Using infrastructure family: %s", suite.uniqueId)

	// Set up consolidated Materialize fixture
	materializePath := helpers.SetupTestWorkspace(t, utils.Azure, suite.uniqueId, utils.MaterializeFixture, stageDir)

	expectedInstanceNamespace := fmt.Sprintf("mz-instance-%s", nameSuffix)
	expectedOperatorNamespace := fmt.Sprintf("mz-operator-%s", nameSuffix)
	expectedCertManagerNamespace := fmt.Sprintf("cert-manager-%s", nameSuffix)
	shortId := strings.Split(suite.uniqueId, "-")[1]
	resourceName := fmt.Sprintf("%s%s", shortId, nameSuffix)

	// Create terraform.tfvars.json file instead of using Vars map
	// This approach is cleaner and follows Terraform best practices
	tfvarsPath := filepath.Join(materializePath, "terraform.tfvars.json")

	// Build variables map for the generic tfvars creation function
	variables := map[string]interface{}{
		// Azure Configuration
		"subscription_id":     subscriptionID,
		"location":            region,
		"resource_group_name": resourceGroupName,
		"prefix":              resourceName,

		// Network Configuration
		"vnet_name":           vnetName,
		"subnet_name":         aksSubnetName,
		"subnet_id":           aksSubnetId,
		"database_subnet_id":  postgresSubnetId,
		"private_dns_zone_id": privateDNSZoneId,

		// AKS Configuration
		"kubernetes_version":                    TestKubernetesVersion,
		"service_cidr":                          TestServiceCIDR,
		"default_node_pool_vm_size":             TestVMSizeSmall,
		"default_node_pool_enable_auto_scaling": false,
		"default_node_pool_node_count":          1,
		"default_node_pool_min_count":           0,
		"default_node_pool_max_count":           0,
		"nodepool_vm_size":                      vmSize,
		"auto_scaling_enabled":                  true,
		"min_nodes":                             TestNodePoolMinNodes,
		"max_nodes":                             TestNodePoolMaxNodes,
		"node_count":                            TestNodePoolNodeCount,
		"disk_size_gb":                          TestDiskSizeMedium,
		"swap_enabled":                          diskEnabled,
		"enable_azure_monitor":                  false,
		"log_analytics_workspace_id":            "",

		// Node Labels
		"node_labels": map[string]string{
			"environment":  helpers.GetEnvironment(),
			"project":      utils.ProjectName,
			"test-run":     suite.uniqueId,
			"disk-enabled": strconv.FormatBool(diskEnabled),
		},

		// Database Configuration
		"databases": []map[string]interface{}{
			{
				"name":      TestDBName,
				"charset":   "UTF8",
				"collation": "en_US.utf8",
			},
		},
		"administrator_login":           TestDBUsername,
		"administrator_password":        TestPassword,
		"sku_name":                      TestDBSKUSmall,
		"postgres_version":              TestPostgreSQLVersion,
		"storage_mb":                    TestStorageSizeSmall,
		"backup_retention_days":         TestBackupRetentionDays,
		"public_network_access_enabled": false,

		// Storage Configuration
		"container_name":        TestStorageContainerName,
		"container_access_type": TestStorageContainerAccessType,

		// Cert Manager Configuration
		"cert_manager_namespace":       expectedCertManagerNamespace,
		"cert_manager_install_timeout": 300,
		"cert_manager_chart_version":   TestCertManagerVersion,

		// Operator Configuration
		"operator_namespace": expectedOperatorNamespace,

		// Materialize Instance Configuration
		"instance_name":                     TestMaterializeInstanceName,
		"instance_namespace":                expectedInstanceNamespace,
		"license_key":                       os.Getenv("MATERIALIZE_LICENSE_KEY"),
		"external_login_password_mz_system": TestPassword,

		// Public Load Balancer Configuration
		"ingress_cidr_blocks": []string{"0.0.0.0/0"},
		"internal":            false,

		// Tags
		"tags": map[string]string{
			"environment":  helpers.GetEnvironment(),
			"project":      utils.ProjectName,
			"test-run":     suite.uniqueId,
			"disk-enabled": strconv.FormatBool(diskEnabled),
		},
	}

	helpers.CreateTfvarsFile(t, tfvarsPath, variables)

	// Upload tfvars to S3 for debugging/cleanup scenarios
	if err := suite.s3Manager.UploadTfvars(t, stageDir, tfvarsPath); err != nil {
		t.Logf("⚠️ Failed to upload tfvars to S3 (non-fatal): %v", err)
	}

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
	materializeOptions.BackendConfig = suite.s3Manager.GetBackendConfig(stageDir)

	// Save terraform options for cleanup
	stageDirPath := filepath.Join(suite.workingDir, stageDir)
	test_structure.SaveTerraformOptions(t, stageDirPath, materializeOptions)

	// Apply
	terraform.InitAndApply(t, materializeOptions)

	// Validate all outputs from the consolidated fixture
	t.Log("🔍 Validating all consolidated fixture outputs...")

	// AKS Cluster Outputs
	clusterName := terraform.Output(t, materializeOptions, "cluster_name")
	clusterEndpoint := terraform.Output(t, materializeOptions, "cluster_endpoint")
	workloadIdentityClientId := terraform.Output(t, materializeOptions, "workload_identity_client_id")
	workloadIdentityPrincipalId := terraform.Output(t, materializeOptions, "workload_identity_principal_id")
	workloadIdentityId := terraform.Output(t, materializeOptions, "workload_identity_id")
	clusterOidcIssuerUrl := terraform.Output(t, materializeOptions, "cluster_oidc_issuer_url")

	// Database Outputs
	serverName := terraform.Output(t, materializeOptions, "server_name")
	serverFQDN := terraform.Output(t, materializeOptions, "server_fqdn")
	adminLogin := terraform.Output(t, materializeOptions, "administrator_login")
	databaseNames := terraform.OutputList(t, materializeOptions, "database_names")

	// Storage Outputs
	storageAccountName := terraform.Output(t, materializeOptions, "storage_account_name")
	storagePrimaryBlobEndpoint := terraform.Output(t, materializeOptions, "storage_primary_blob_endpoint")
	storageContainerName := terraform.Output(t, materializeOptions, "storage_container_name")

	// Materialize Backend URLs
	metadataBackendURL := terraform.Output(t, materializeOptions, "metadata_backend_url")
	persistBackendURL := terraform.Output(t, materializeOptions, "persist_backend_url")

	// Materialize Operator Outputs
	operatorNamespace := terraform.Output(t, materializeOptions, "operator_namespace")

	// Materialize Instance Outputs
	instanceResourceId := terraform.Output(t, materializeOptions, "instance_resource_id")
	externalLoginPassword := terraform.Output(t, materializeOptions, "external_login_password")

	// Load Balancer Outputs
	consoleLoadBalancerIP := terraform.Output(t, materializeOptions, "console_load_balancer_ip")
	balancerdLoadBalancerIP := terraform.Output(t, materializeOptions, "balancerd_load_balancer_ip")

	// Certificate Outputs
	clusterIssuerName := terraform.Output(t, materializeOptions, "cluster_issuer_name")

	// Comprehensive validation
	t.Log("✅ Validating AKS Cluster Outputs...")
	suite.NotEmpty(clusterName, "AKS cluster name should not be empty")
	suite.NotEmpty(clusterEndpoint, "AKS cluster endpoint should not be empty")
	suite.NotEmpty(workloadIdentityClientId, "Workload identity client ID should not be empty")
	suite.NotEmpty(workloadIdentityPrincipalId, "Workload identity principal ID should not be empty")
	suite.NotEmpty(workloadIdentityId, "Workload identity ID should not be empty")
	suite.NotEmpty(clusterOidcIssuerUrl, "Cluster OIDC issuer URL should not be empty")

	t.Log("✅ Validating Database Outputs...")
	suite.NotEmpty(serverName, "Database server name should not be empty")
	suite.NotEmpty(serverFQDN, "Database server FQDN should not be empty")
	suite.Equal(TestDBUsername, adminLogin, "Database username should match the configured value")
	suite.NotEmpty(databaseNames, "Database names list should not be empty")
	suite.Contains(databaseNames, TestDBName, "Expected database '%s' should be created", TestDBName)

	t.Log("✅ Validating Storage Outputs...")
	suite.NotEmpty(storageAccountName, "Storage account name should not be empty")
	suite.NotEmpty(storagePrimaryBlobEndpoint, "Storage primary blob endpoint should not be empty")
	suite.NotEmpty(storageContainerName, "Storage container name should not be empty")

	t.Log("✅ Validating Materialize Backend URLs...")
	suite.NotEmpty(metadataBackendURL, "Metadata backend URL should not be empty")
	suite.NotEmpty(persistBackendURL, "Persist backend URL should not be empty")

	t.Log("✅ Validating Materialize Operator Outputs...")
	suite.NotEmpty(operatorNamespace, "Operator namespace should not be empty")
	suite.Equal(expectedOperatorNamespace, operatorNamespace, "Operator namespace should match expected value")

	t.Log("✅ Validating Materialize Instance Outputs...")
	suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")
	suite.NotEmpty(externalLoginPassword, "External login password should not be empty")

	t.Log("✅ Validating Load Balancer Outputs...")
	suite.NotEmpty(consoleLoadBalancerIP, "Console load balancer IP should not be empty")
	suite.NotEmpty(balancerdLoadBalancerIP, "Balancerd load balancer IP should not be empty")

	t.Log("✅ Validating Certificate Outputs...")
	suite.NotEmpty(clusterIssuerName, "Cluster issuer name should not be empty")

	t.Logf("✅ Complete Materialize stack created successfully:")
	t.Logf("  💾 Disk Enabled: %t", diskEnabled)

	// AKS Cluster Outputs
	t.Logf("🔧 AKS CLUSTER OUTPUTS:")
	t.Logf("  📛 Cluster Name: %s", clusterName)
	t.Logf("  🔗 Cluster Endpoint: %s", clusterEndpoint)
	t.Logf("  🆔 Workload Identity Client ID: %s", workloadIdentityClientId)
	t.Logf("  🆔 Workload Identity Principal ID: %s", workloadIdentityPrincipalId)
	t.Logf("  🆔 Workload Identity ID: %s", workloadIdentityId)
	t.Logf("  🌐 Cluster OIDC Issuer URL: %s", clusterOidcIssuerUrl)

	// Database Outputs
	t.Logf("🗄️ DATABASE OUTPUTS:")
	t.Logf("  🔗 Server Name: %s", serverName)
	t.Logf("  🔗 Server FQDN: %s", serverFQDN)
	t.Logf("  👤 Administrator Login: %s", adminLogin)
	t.Logf("  🗄️ Database Names: %v", databaseNames)

	// Storage Outputs
	t.Logf("☁️ STORAGE OUTPUTS:")
	t.Logf("  🗄️ Storage Account Name: %s", storageAccountName)
	t.Logf("  🌐 Storage Primary Blob Endpoint: %s", storagePrimaryBlobEndpoint)
	t.Logf("  🗄️ Storage Container Name: %s", storageContainerName)

	// Materialize Backend URLs
	t.Logf("🔗 MATERIALIZE BACKEND URLS:")
	t.Logf("  🗄️ Metadata Backend URL: %s", metadataBackendURL)
	t.Logf("  💾 Persist Backend URL: %s", persistBackendURL)

	// Materialize Operator Outputs
	t.Logf("⚙️ MATERIALIZE OPERATOR OUTPUTS:")
	t.Logf("  📦 Operator Namespace: %s", operatorNamespace)

	// Materialize Instance Outputs
	t.Logf("🚀 MATERIALIZE INSTANCE OUTPUTS:")
	t.Logf("  🆔 Instance Resource ID: %s", instanceResourceId)
	t.Logf("  🔐 External Login Password: [REDACTED]")

	// Load Balancer Outputs
	t.Logf("🌐 LOAD BALANCER OUTPUTS:")
	t.Logf("  🌐 Console Load Balancer IP: %s", consoleLoadBalancerIP)
	t.Logf("  🌐 Balancerd Load Balancer IP: %s", balancerdLoadBalancerIP)

	// Certificate Outputs
	t.Logf("🔐 CERTIFICATE OUTPUTS:")
	t.Logf("  📜 Cluster Issuer Name: %s", clusterIssuerName)
}

func (suite *StagedDeploymentSuite) useExistingNetwork() string {
	t := suite.T()
	// Get the most recent state directory
	testCloudDir := filepath.Join(dir.GetProjectRootDir(), utils.MainTestDir, utils.Azure)
	latestDirPath, err := dir.GetLastRunTestStageDir(testCloudDir)
	if err != nil {
		t.Fatalf("❌ Cannot skip network creation: %v", err)
	}

	// Use the full path returned by the helper
	suite.workingDir = latestDirPath
	latestDir := filepath.Base(latestDirPath)
	// Load and return the unique ID
	uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
	if uniqueId == "" {
		t.Fatal("❌ Cannot use existing network: Unique ID not found. Run network setup stage first.")
	}
	suite.uniqueId = uniqueId

	// Validate that network was created successfully by checking VNet name
	networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
	vnetName := test_structure.LoadString(t, networkStageDir, "vnet_name")
	if vnetName == "" {
		t.Fatalf("❌ Cannot skip network creation: VNet name is empty in state directory %s", latestDir)
	}

	// Initialize S3 backend manager for existing network
	s3Manager, err := s3backend.InitManager(t, utils.Azure, uniqueId)
	if err != nil {
		t.Fatalf("❌ Failed to initialize S3 backend manager: %v", err)
	}
	suite.s3Manager = s3Manager

	t.Logf("♻️ Using existing network from: %s (ID: %s, VNet: %s)", suite.workingDir, uniqueId, vnetName)
	return uniqueId
}

// TestStagedDeploymentSuite runs the test suite
func TestStagedDeploymentSuite(t *testing.T) {
	suite.Run(t, new(StagedDeploymentSuite))
}
