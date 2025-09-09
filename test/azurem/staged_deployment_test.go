package test

import (
	"fmt"
	"os"
	"path/filepath"
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

// StagedDeploymentSuite tests the full Azure infrastructure deployment in stages
type StagedDeploymentSuite struct {
	basesuite.BaseTestSuite
	workingDir string
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
		if networkOptions := test_structure.LoadTerraformOptions(t, suite.workingDir); networkOptions != nil {
			t.Logf("🗑️ Cleaning up network...")
			terraform.Destroy(t, networkOptions)
			t.Logf("✅ Network cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.Azure, uniqueId, utils.NetworkingDir)

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

	test_structure.RunTestStage(t, "cleanup_aks_disk_enabled", func() {
		suite.cleanupStage("cleanup_aks_disk_enabled", utils.AKSDiskEnabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_database_disk_enabled", func() {
		suite.cleanupStage("cleanup_database_disk_enabled", utils.DatabaseDiskEnabledDir)
	})

	t.Logf("✅ Disk Enabled Cleanup completed successfully")
}

func (suite *StagedDeploymentSuite) testDiskDisabledCleanup() {
	t := suite.T()
	t.Log("Running Disk Disabled Cleanup Tests")

	test_structure.RunTestStage(t, "cleanup_materialize_disk_disabled", func() {
		suite.cleanupStage("cleanup_materialize_disk_disabled", utils.MaterializeDiskDisabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_aks_disk_disabled", func() {
		suite.cleanupStage("cleanup_aks_disk_disabled", utils.AKSDiskDisabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_database_disk_disabled", func() {
		suite.cleanupStage("cleanup_database_disk_disabled", utils.DatabaseDiskDisabledDir)
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
	helpers.CleanupTestWorkspace(t, utils.Azure, uniqueId, stageDir)
}

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → (disk-enabled-setup) → (disk-disabled-setup)
func (suite *StagedDeploymentSuite) TestFullDeployment() {
	t := suite.T()
	subscriptionID := os.Getenv("ARM_SUBSCRIPTION_ID")
	testRegion := os.Getenv("TEST_REGION")
	if testRegion == "" {
		testRegion = TestRegion
	}

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
			uniqueId = generateAzureCompliantID()
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
		networkingPath := helpers.SetupTestWorkspace(t, utils.Azure, uniqueId, utils.NetworkingDir, utils.NetworkingDir)

		networkOptions := &terraform.Options{
			TerraformDir: networkingPath,
			Vars: map[string]interface{}{
				"subscription_id":      subscriptionID,
				"resource_group_name":  fmt.Sprintf("%s-rg", shortId),
				"location":             testRegion,
				"prefix":               shortId,
				"vnet_address_space":   TestVNetAddressSpace,
				"aks_subnet_cidr":      TestAKSSubnetCIDR,
				"postgres_subnet_cidr": TestPostgresSubnetCIDR,
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
		resourceGroupName := terraform.Output(t, networkOptions, "resource_group_name")
		vnetId := terraform.Output(t, networkOptions, "vnet_id")
		vnetName := terraform.Output(t, networkOptions, "vnet_name")
		aksSubnetId := terraform.Output(t, networkOptions, "aks_subnet_id")
		aksSubnetName := terraform.Output(t, networkOptions, "aks_subnet_name")
		postgresSubnetId := terraform.Output(t, networkOptions, "postgres_subnet_id")
		privateDNSZoneId := terraform.Output(t, networkOptions, "private_dns_zone_id")

		// Save all outputs and resource IDs
		test_structure.SaveString(t, suite.workingDir, "resource_group_name", resourceGroupName)
		test_structure.SaveString(t, suite.workingDir, "vnet_id", vnetId)
		test_structure.SaveString(t, suite.workingDir, "vnet_name", vnetName)
		test_structure.SaveString(t, suite.workingDir, "aks_subnet_id", aksSubnetId)
		test_structure.SaveString(t, suite.workingDir, "aks_subnet_name", aksSubnetName)
		test_structure.SaveString(t, suite.workingDir, "postgres_subnet_id", postgresSubnetId)
		test_structure.SaveString(t, suite.workingDir, "private_dns_zone_id", privateDNSZoneId)
		test_structure.SaveString(t, suite.workingDir, "test_region", testRegion)

		t.Logf("✅ Network infrastructure created:")
		t.Logf("  🏠 Resource Group: %s", resourceGroupName)
		t.Logf("  🌐 VNet: %s (%s)", vnetName, vnetId)
		t.Logf("  🏠 AKS Subnet: %s", aksSubnetName)
		t.Logf("  🏷️ Resource ID: %s", uniqueId)

	})
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Test Disk Enabled Setup
	suite.testDiskEnabledSetup(subscriptionID, testRegion)

	// Test Disk Disabled Setup
	suite.testDiskDisabledSetup(subscriptionID, testRegion)
}

func (suite *StagedDeploymentSuite) testDiskEnabledSetup(subscriptionID, testRegion string) {
	t := suite.T()
	t.Log("Running Disk Enabled Setup Tests")

	// Stage 2: AKS Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_aks_disk_enabled", func() {
		suite.setupAKSStage("setup_aks_disk_enabled", utils.AKSDiskEnabledDir, subscriptionID, testRegion,
			utils.DiskEnabledShortSuffix, "true", TestAKSDiskEnabledVMSize)
	})

	test_structure.RunTestStage(t, "setup_database_disk_enabled", func() {
		suite.setupDatabaseStage("setup_database_disk_enabled", utils.DatabaseDiskEnabledDir, subscriptionID, testRegion,
			utils.DiskEnabledShortSuffix, "true")
	})

	// Stage 5: Materialize Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_materialize_disk_enabled", func() {
		suite.setupMaterializeStage("setup_materialize_disk_enabled", utils.MaterializeDiskEnabledDir, subscriptionID, testRegion,
			utils.DiskEnabledShortSuffix, "true")
	})
	t.Logf("✅ Disk Enabled Setup completed successfully")
}

func (suite *StagedDeploymentSuite) testDiskDisabledSetup(subscriptionID, testRegion string) {
	t := suite.T()
	t.Log("Running Disk Disabled Setup Tests")

	// Stage 2: AKS Setup (Disk Disabled)
	test_structure.RunTestStage(t, "setup_aks_disk_disabled", func() {
		suite.setupAKSStage("setup_aks_disk_disabled", utils.AKSDiskDisabledDir, subscriptionID, testRegion,
			utils.DiskDisabledShortSuffix, "false", TestAKSDiskDisabledVMSize)
	})

	test_structure.RunTestStage(t, "setup_database_disk_disabled", func() {
		suite.setupDatabaseStage("setup_database_disk_disabled", utils.DatabaseDiskDisabledDir, subscriptionID, testRegion,
			utils.DiskDisabledShortSuffix, "false")
	})

	// Stage 5: Materialize Setup (Disk Disabled)
	test_structure.RunTestStage(t, "setup_materialize_disk_disabled", func() {
		suite.setupMaterializeStage("setup_materialize_disk_disabled", utils.MaterializeDiskDisabledDir, subscriptionID, testRegion,
			utils.DiskDisabledShortSuffix, "false")
	})
	t.Logf("✅ Disk Disabled Setup completed successfully")
}

func (suite *StagedDeploymentSuite) setupAKSStage(stage, stageDir, subscriptionID, region, nameSuffix, diskEnabled, vmSize string) {
	t := suite.T()
	t.Logf("🔧 Setting up AKS stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create AKS: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data
	resourceGroupName := test_structure.LoadString(t, suite.workingDir, "resource_group_name")
	vnetName := test_structure.LoadString(t, suite.workingDir, "vnet_name")
	aksSubnetId := test_structure.LoadString(t, suite.workingDir, "aks_subnet_id")
	aksSubnetName := test_structure.LoadString(t, suite.workingDir, "aks_subnet_name")
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
	shortId := strings.Split(resourceId, "-")[1]

	// Validate required network data exists
	if resourceGroupName == "" || vnetName == "" || aksSubnetId == "" || resourceId == "" {
		t.Fatal("❌ Cannot create AKS: Missing network data. Run network setup stage first.")
	}

	t.Logf("🔗 Using infrastructure family: %s for AKS (disk-enabled: %s)", resourceId, diskEnabled)

	// Set up AKS example
	aksPath := helpers.SetupTestWorkspace(t, utils.Azure, resourceId, utils.AKSDir, stageDir)

	aksOptions := &terraform.Options{
		TerraformDir: aksPath,
		Vars: map[string]interface{}{
			"subscription_id":              subscriptionID,
			"resource_group_name":          resourceGroupName,
			"location":                     region,
			"prefix":                       fmt.Sprintf("%s%s", shortId, nameSuffix),
			"vnet_name":                    vnetName,
			"subnet_name":                  aksSubnetName,
			"subnet_id":                    aksSubnetId,
			"kubernetes_version":           TestKubernetesVersion,
			"service_cidr":                 TestServiceCIDR,
			"default_node_pool_vm_size":    TestVMSizeSmall,
			"default_node_pool_node_count": 2,
			"nodepool_vm_size":             vmSize,
			"auto_scaling_enabled":         true,
			"min_nodes":                    TestNodePoolMinNodes,
			"max_nodes":                    TestNodePoolMaxNodes,
			"node_count":                   TestNodePoolNodeCount,
			"disk_size_gb":                 TestDiskSizeMedium,
			"enable_disk_setup":            diskEnabled == "true",
			"disk_setup_image":             "materialize/ephemeral-storage-setup-image:v0.1.1",
			"enable_azure_monitor":         false,
			"log_analytics_workspace_id":   "",
			"tags": map[string]string{
				"Environment": "test",
				"Project":     "materialize",
				"TestRun":     resourceId,
				"DiskEnabled": diskEnabled,
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
	test_structure.SaveTerraformOptions(t, stageDirPath, aksOptions)

	// Apply
	terraform.InitAndApply(t, aksOptions)

	// Validate and save outputs
	clusterName := terraform.Output(t, aksOptions, "cluster_name")
	clusterEndpoint := terraform.Output(t, aksOptions, "cluster_endpoint")
	workloadIdentityClientId := terraform.Output(t, aksOptions, "workload_identity_client_id")
	clusterIdentityPrincipalId := terraform.Output(t, aksOptions, "cluster_identity_principal_id")
	kubeConfigList := terraform.OutputListOfObjects(t, aksOptions, "kube_config")
	kubeConfigRaw := kubeConfigList[0]

	suite.NotEmpty(clusterName, "AKS cluster name should not be empty")
	suite.NotEmpty(kubeConfigRaw, "Kube config should not be empty")

	// Save AKS outputs for Materialize stage
	test_structure.SaveString(t, stageDirPath, "cluster_name", clusterName)
	test_structure.SaveString(t, stageDirPath, "cluster_endpoint", clusterEndpoint)
	test_structure.SaveString(t, stageDirPath, "workload_identity_client_id", workloadIdentityClientId)
	test_structure.SaveString(t, stageDirPath, "cluster_identity_principal_id", clusterIdentityPrincipalId)

	// Save kube config components separately for easier loading
	test_structure.SaveString(t, stageDirPath, "kube_config_client_certificate", kubeConfigRaw["client_certificate"].(string))
	test_structure.SaveString(t, stageDirPath, "kube_config_client_key", kubeConfigRaw["client_key"].(string))
	test_structure.SaveString(t, stageDirPath, "kube_config_cluster_ca_certificate", kubeConfigRaw["cluster_ca_certificate"].(string))

	t.Logf("✅ AKS cluster created successfully:")
	t.Logf("  🏷️ Cluster Name: %s", clusterName)
	t.Logf("  🔗 Endpoint: %s", clusterEndpoint)
	t.Logf("  🆔 Workload Identity Client ID: %s", workloadIdentityClientId)
}

func (suite *StagedDeploymentSuite) setupDatabaseStage(stage, stageDir, subscriptionID, region, nameSuffix, diskEnabled string) {
	t := suite.T()
	t.Logf("🔧 Setting up Database stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create database: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data
	resourceGroupName := test_structure.LoadString(t, suite.workingDir, "resource_group_name")
	postgresSubnetId := test_structure.LoadString(t, suite.workingDir, "postgres_subnet_id")
	privateDNSZoneId := test_structure.LoadString(t, suite.workingDir, "private_dns_zone_id")
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
	shortId := strings.Split(resourceId, "-")[1]

	// Validate required network data exists
	if resourceGroupName == "" || postgresSubnetId == "" || privateDNSZoneId == "" || resourceId == "" {
		t.Fatal("❌ Cannot create database: Missing network data. Run network setup stage first.")
	}

	t.Logf("🔗 Using infrastructure family: %s for Database (disk-enabled: %s)", resourceId, diskEnabled)

	// Set up database example
	databasePath := helpers.SetupTestWorkspace(t, utils.Azure, resourceId, utils.DataBaseDir, stageDir)

	dbOptions := &terraform.Options{
		TerraformDir: databasePath,
		Vars: map[string]interface{}{
			"subscription_id":     subscriptionID,
			"resource_group_name": resourceGroupName,
			"location":            region,
			"prefix":              fmt.Sprintf("%s%s", shortId, nameSuffix),
			"subnet_id":           postgresSubnetId,
			"private_dns_zone_id": privateDNSZoneId,
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
			"tags": map[string]string{
				"Environment": "test",
				"Project":     "materialize",
				"TestRun":     resourceId,
				"DiskEnabled": diskEnabled,
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
	serverName := terraform.Output(t, dbOptions, "server_name")
	serverFQDN := terraform.Output(t, dbOptions, "server_fqdn")
	adminLogin := terraform.Output(t, dbOptions, "administrator_login")
	adminPassword := terraform.Output(t, dbOptions, "administrator_password")
	databaseNames := terraform.OutputList(t, dbOptions, "database_names")
	databases := terraform.OutputMapOfObjects(t, dbOptions, "databases")

	// Comprehensive validation
	suite.NotEmpty(serverName, "Database server name should not be empty")
	suite.NotEmpty(serverFQDN, "Database server FQDN should not be empty")
	suite.Equal(TestDBUsername, adminLogin, "Database username should match the configured value")
	suite.NotEmpty(adminPassword, "Database password should not be empty")

	// Validate databases
	suite.NotEmpty(databaseNames, "Database names list should not be empty")
	suite.Contains(databaseNames, TestDBName, "Expected database '%s' should be created", TestDBName)
	suite.NotEmpty(databases, "Databases map should not be empty")
	suite.Contains(databases, TestDBName, "Expected database '%s' should exist in databases map", TestDBName)

	// Validate the specific database configuration
	materializeDB, exists := databases[TestDBName]
	suite.True(exists, "Materialize test database should exist")
	if exists {
		dbMap := materializeDB.(map[string]interface{})
		suite.Equal(TestDBName, dbMap["name"], "Database name should match expected value")
		suite.NotEmpty(dbMap["charset"], "Database charset should be set")
		suite.NotEmpty(dbMap["collation"], "Database collation should be set")
	}

	// Save database outputs for future stages
	test_structure.SaveString(t, stageDirPath, "server_name", serverName)
	test_structure.SaveString(t, stageDirPath, "server_fqdn", serverFQDN)
	test_structure.SaveString(t, stageDirPath, "administrator_login", adminLogin)
	test_structure.SaveString(t, stageDirPath, "administrator_password", adminPassword)

	databaseNamesString := strings.Join(databaseNames, ",")
	// Save database names and configuration for Materialize test
	test_structure.SaveString(t, stageDirPath, "database_names", databaseNamesString)

	t.Logf("✅ Database created successfully:")
	t.Logf("  🔗 Server Name: %s", serverName)
	t.Logf("  🔗 FQDN: %s", serverFQDN)
	t.Logf("  👤 Username: %s", adminLogin)
	t.Logf("  🗄️ Database Names: %v", databaseNames)

}

func (suite *StagedDeploymentSuite) setupMaterializeStage(stage, stageDir, subscriptionID, region, nameSuffix, diskEnabled string) {
	t := suite.T()
	t.Logf("🔧 Setting up Materialize stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot install Materialize: Working directory not set. Run network setup stage first.")
	}

	// Load network data
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
	resourceGroupName := test_structure.LoadString(t, suite.workingDir, "resource_group_name")
	aksSubnetId := test_structure.LoadString(t, suite.workingDir, "aks_subnet_id")
	shortId := strings.Split(resourceId, "-")[1]

	// Load AKS data
	aksStageDir := utils.AKSDiskDisabledDir
	if diskEnabled == "true" {
		aksStageDir = utils.AKSDiskEnabledDir
	}
	aksStageDirFullPath := filepath.Join(suite.workingDir, aksStageDir)
	clusterEndpoint := test_structure.LoadString(t, aksStageDirFullPath, "cluster_endpoint")
	clusterIdentityPrincipalId := test_structure.LoadString(t, aksStageDirFullPath, "cluster_identity_principal_id")

	// Load database data
	databaseStageDir := utils.DatabaseDiskDisabledDir
	if diskEnabled == "true" {
		databaseStageDir = utils.DatabaseDiskEnabledDir
	}
	dbStageDirFullPath := filepath.Join(suite.workingDir, databaseStageDir)
	databaseHost := test_structure.LoadString(t, dbStageDirFullPath, "server_fqdn")
	databaseAdminLogin := test_structure.LoadString(t, dbStageDirFullPath, "administrator_login")
	databaseAdminPassword := test_structure.LoadString(t, dbStageDirFullPath, "administrator_password")
	databaseNames := test_structure.LoadString(t, dbStageDirFullPath, "database_names")
	databaseName := strings.Split(databaseNames, ",")[0]

	t.Logf("🔗 Using database configuration:")
	t.Logf("  🏠 Host: %s", databaseHost)
	t.Logf("  🗄️ Database: %s", databaseName)
	t.Logf("  👤 Admin User: %s", databaseAdminLogin)

	// Load kube config components from saved outputs
	kubeConfigClientCert := test_structure.LoadString(t, aksStageDirFullPath, "kube_config_client_certificate")
	kubeConfigClientKey := test_structure.LoadString(t, aksStageDirFullPath, "kube_config_client_key")
	kubeConfigClusterCA := test_structure.LoadString(t, aksStageDirFullPath, "kube_config_cluster_ca_certificate")

	// Validate kube config components
	if kubeConfigClientCert == "" || kubeConfigClientKey == "" || kubeConfigClusterCA == "" {
		t.Fatal("❌ Cannot setup Materialize: Missing kube config components from AKS stage")
	}

	// Extract kube config components
	kubeConfig := map[string]interface{}{
		"client_certificate":     kubeConfigClientCert,
		"client_key":             kubeConfigClientKey,
		"cluster_ca_certificate": kubeConfigClusterCA,
	}

	t.Logf("🔗 Using infrastructure family: %s for Materialize (disk-enabled: %s)", resourceId, diskEnabled)

	// Set up Materialize example
	materializePath := helpers.SetupTestWorkspace(t, utils.Azure, resourceId, utils.MaterializeDir, stageDir)

	expectedInstanceNamespace := fmt.Sprintf("mz-instance-%s", nameSuffix)
	expectedOperatorNamespace := fmt.Sprintf("mz-operator-%s", nameSuffix)
	expectedOpenEbsNamespace := fmt.Sprintf("openebs-%s", nameSuffix)
	expectedCertManagerNamespace := fmt.Sprintf("cert-manager-%s", nameSuffix)
	enableDiskSupport := diskEnabled == "true"

	materializeOptions := &terraform.Options{
		TerraformDir: materializePath,
		Vars: map[string]interface{}{
			"subscription_id":     subscriptionID,
			"location":            region,
			"resource_group_name": resourceGroupName,
			"prefix":              fmt.Sprintf("%s%s", shortId, nameSuffix),

			// AKS details
			"cluster_endpoint":              clusterEndpoint,
			"cluster_identity_principal_id": clusterIdentityPrincipalId,
			"subnets":                       []string{aksSubnetId},
			"kube_config":                   kubeConfig,

			// Database details
			"database_host": databaseHost,
			"database_name": databaseName,
			"database_admin_user": map[string]interface{}{
				"name":     databaseAdminLogin,
				"password": databaseAdminPassword,
			},

			// Storage details
			"storage_config": map[string]interface{}{
				"account_tier":             TestStorageAccountTier,
				"account_replication_type": TestStorageReplicationType,
				"account_kind":             TestStorageAccountKind,
				"container_name":           TestStorageContainerName,
				"container_access_type":    TestStorageContainerAccessType,
			},

			"tags": map[string]string{
				"Environment": "test",
				"Project":     "materialize",
				"TestRun":     resourceId,
				"DiskEnabled": diskEnabled,
			},

			// Cert Manager details
			"install_cert_manager":         true,
			"cert_manager_namespace":       expectedCertManagerNamespace,
			"cert_manager_install_timeout": 300,
			"cert_manager_chart_version":   TestCertManagerVersion,

			// OpenEBS details
			"enable_disk_support": enableDiskSupport,
			"openebs_namespace":   expectedOpenEbsNamespace,
			"openebs_version":     TestOpenEbsVersion,

			// Operator details
			"operator_namespace": expectedOperatorNamespace,

			// Materialize instance details
			"instance_name":                TestMaterializeInstanceName,
			"instance_namespace":           expectedInstanceNamespace,
			"install_materialize_instance": false, // Phase 1: operator only
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

	t.Logf("✅ Phase 1: Materialize operator installed on cluster where disk-enabled: %s", diskEnabled)

	// Phase 2: Update variables for instance deployment
	materializeOptions.Vars["install_materialize_instance"] = true

	// Phase 2: Apply with instance enabled
	terraform.Apply(t, materializeOptions)

	// Save Materialize outputs for subsequent stages
	storageAccountName := terraform.Output(t, materializeOptions, "storage_account_name")
	storageAccountKey := terraform.Output(t, materializeOptions, "storage_account_key")
	storagePrimaryBlobEndpoint := terraform.Output(t, materializeOptions, "storage_primary_blob_endpoint")
	storagePrimaryBlobSASToken := terraform.Output(t, materializeOptions, "storage_primary_blob_sas_token")
	storageContainerName := terraform.Output(t, materializeOptions, "storage_container_name")
	metadataBackendURL := terraform.Output(t, materializeOptions, "metadata_backend_url")
	persistBackendURL := terraform.Output(t, materializeOptions, "persist_backend_url")
	instanceInstalled := terraform.Output(t, materializeOptions, "instance_installed")
	instanceResourceId := terraform.Output(t, materializeOptions, "instance_resource_id")
	externalLoginPassword := terraform.Output(t, materializeOptions, "external_login_password")
	clusterIssuerName := terraform.Output(t, materializeOptions, "cluster_issuer_name")
	openebsInstalled := terraform.Output(t, materializeOptions, "openebs_installed")
	operatorNamespace := terraform.Output(t, materializeOptions, "operator_namespace")
	loadBalancerInstalled := terraform.Output(t, materializeOptions, "load_balancer_installed")
	consoleLoadBalancerIP := terraform.Output(t, materializeOptions, "console_load_balancer_ip")
	balancerdLoadBalancerIP := terraform.Output(t, materializeOptions, "balancerd_load_balancer_ip")

	// Validation
	suite.Equal("true", instanceInstalled, "Materialize instance should be installed")
	suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")
	suite.NotEmpty(externalLoginPassword, "External login password should not be empty")

	// Storage validation
	suite.NotEmpty(storageAccountName, "Storage account name should not be empty")
	suite.NotEmpty(storageAccountKey, "Storage account key should not be empty")
	suite.NotEmpty(storagePrimaryBlobEndpoint, "Storage primary blob endpoint should not be empty")
	suite.NotEmpty(storagePrimaryBlobSASToken, "Storage primary blob SAS token should not be empty")
	suite.NotEmpty(storageContainerName, "Storage container name should not be empty")

	// Backend URLs validation
	suite.NotEmpty(metadataBackendURL, "Metadata backend URL should not be empty")
	suite.NotEmpty(persistBackendURL, "Persist backend URL should not be empty")

	// Certificate validation
	suite.NotEmpty(clusterIssuerName, "Cluster issuer name should not be empty")

	// Namespace validation
	suite.NotEmpty(operatorNamespace, "Operator namespace should not be empty")
	suite.Equal(expectedOperatorNamespace, operatorNamespace, "Operator namespace should match expected value")

	// Load balancer validation
	suite.Equal("true", loadBalancerInstalled, "Load balancer should be installed")
	suite.NotEmpty(consoleLoadBalancerIP, "Console load balancer IP should not be empty")
	suite.NotEmpty(balancerdLoadBalancerIP, "Balancerd load balancer IP should not be empty")
	if enableDiskSupport {
		suite.Equal("true", openebsInstalled, "OpenEBS should be installed if disk support is enabled")
	} else {
		suite.Equal("false", openebsInstalled, "OpenEBS should not be installed if disk support is disabled")
	}

	t.Logf("✅ Phase 2: Materialize instance created successfully:")
	if enableDiskSupport {
		openebsNamespace := terraform.Output(t, materializeOptions, "openebs_namespace")
		suite.NotEmpty(openebsNamespace, "OpenEBS namespace should not be empty when disk support is enabled")
		suite.Equal(expectedOpenEbsNamespace, openebsNamespace, "OpenEBS namespace should match expected value")
		test_structure.SaveString(t, stageDirFullPath, "openebs_namespace", openebsNamespace)
		t.Logf("  🗄️ OpenEBS Namespace: %s", openebsNamespace)
	}

	t.Logf("  🗄️ Instance Resource ID: %s", instanceResourceId)
	t.Logf("  🗄️ Instance Installed: %s", instanceInstalled)
	t.Logf("  🔐 External Login Password: [REDACTED]")
	t.Logf("  🗄️ Storage Account: %s", storageAccountName)
	t.Logf("  🔐 Storage Account Key: [REDACTED]")
	t.Logf("  🗄️ Storage Primary Blob Endpoint: %s", storagePrimaryBlobEndpoint)
	t.Logf("  🔐 Storage Primary Blob SAS Token: [REDACTED]")
	t.Logf("  🗄️ Storage Container Name: %s", storageContainerName)
	t.Logf("  🗄️ Metadata Backend URL: %s", metadataBackendURL)
	t.Logf("  🗄️ Persist Backend URL: %s", persistBackendURL)
	t.Logf("  🗄️ Cluster Issuer Name: %s", clusterIssuerName)
	t.Logf("  🗄️ OpenEBS Installed: %s", openebsInstalled)
	t.Logf("  🗄️ Operator Namespace: %s", operatorNamespace)
	t.Logf("  🗄️ Load Balancer Installed: %s", loadBalancerInstalled)
	t.Logf("  🗄️ Console Load Balancer IP: %s", consoleLoadBalancerIP)
	t.Logf("  🗄️ Balancerd Load Balancer IP: %s", balancerdLoadBalancerIP)

	test_structure.SaveString(t, stageDirFullPath, "instance_resource_id", instanceResourceId)
	test_structure.SaveString(t, stageDirFullPath, "instance_installed", instanceInstalled)
	test_structure.SaveString(t, stageDirFullPath, "external_login_password", externalLoginPassword)
	test_structure.SaveString(t, stageDirFullPath, "storage_account_name", storageAccountName)
	test_structure.SaveString(t, stageDirFullPath, "storage_account_key", storageAccountKey)
	test_structure.SaveString(t, stageDirFullPath, "storage_primary_blob_endpoint", storagePrimaryBlobEndpoint)
	test_structure.SaveString(t, stageDirFullPath, "storage_primary_blob_sas_token", storagePrimaryBlobSASToken)
	test_structure.SaveString(t, stageDirFullPath, "storage_container_name", storageContainerName)
	test_structure.SaveString(t, stageDirFullPath, "metadata_backend_url", metadataBackendURL)
	test_structure.SaveString(t, stageDirFullPath, "persist_backend_url", persistBackendURL)
	test_structure.SaveString(t, stageDirFullPath, "cluster_issuer_name", clusterIssuerName)
	test_structure.SaveString(t, stageDirFullPath, "openebs_installed", openebsInstalled)
	test_structure.SaveString(t, stageDirFullPath, "operator_namespace", operatorNamespace)
	test_structure.SaveString(t, stageDirFullPath, "load_balancer_installed", loadBalancerInstalled)
	test_structure.SaveString(t, stageDirFullPath, "console_load_balancer_ip", consoleLoadBalancerIP)
	test_structure.SaveString(t, stageDirFullPath, "balancerd_load_balancer_ip", balancerdLoadBalancerIP)
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
	vnetName := test_structure.LoadString(t, suite.workingDir, "vnet_name")
	if vnetName == "" {
		t.Fatalf("❌ Cannot skip network creation: VNet name is empty in state directory %s", latestDir)
	}

	t.Logf("♻️ Skipping network creation, using existing: %s (ID: %s)", vnetName, latestDir)
}

// TestStagedDeploymentSuite runs the test suite
func TestStagedDeploymentSuite(t *testing.T) {
	suite.Run(t, new(StagedDeploymentSuite))
}
