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

// StagedDeploymentTestSuite tests the full Azure infrastructure deployment in stages
type StagedDeploymentTestSuite struct {
	basesuite.BaseTestSuite
	workingDir string
}

// SetupSuite initializes the test suite
func (suite *StagedDeploymentTestSuite) SetupSuite() {
	configurations := config.GetCommonConfigurations()
	configurations = append(configurations, getRequiredAzureConfigurations()...)
	suite.SetupBaseSuite("Azure Staged Deployment", utils.Azure, configurations)
	// Working directory will be set dynamically based on uniqueId
	suite.workingDir = "" // Will be set in network stage
}

// TearDownSuite cleans up the test suite
func (suite *StagedDeploymentTestSuite) TearDownSuite() {
	t := suite.T()
	t.Logf("🧹 Starting cleanup stages for: %s", suite.SuiteName)
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

func (suite *StagedDeploymentTestSuite) testDiskEnabledCleanup() {
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

func (suite *StagedDeploymentTestSuite) cleanupStage(stageName, stageDir string) {
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
// Stages: Network → (disk-enabled-setup)
func (suite *StagedDeploymentTestSuite) TestFullDeployment() {
	t := suite.T()
	subscriptionID := os.Getenv("ARM_SUBSCRIPTION_ID")
	testRegion := os.Getenv("TEST_REGION")
	if testRegion == "" {
		testRegion = TestRegion
	}

	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		// Generate unique ID for this infrastructure family
		if os.Getenv("USE_EXISTING_NETWORK") != "" {
			suite.useExistingNetwork()
		} else {
			uniqueId := generateAzureCompliantID()
			// Short ID will used as resource name prefix so that we don't exceed the length limit
			shortId := strings.Split(uniqueId, "-")[1]
			suite.workingDir = fmt.Sprintf("%s/%s", TestRunsDir, uniqueId)
			os.MkdirAll(suite.workingDir, 0755)
			t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
			t.Logf("📁 Test Stage Output directory: %s", suite.workingDir)

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
			test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)
			test_structure.SaveString(t, suite.workingDir, "test_region", testRegion)

			t.Logf("✅ Network infrastructure created:")
			t.Logf("  🏠 Resource Group: %s", resourceGroupName)
			t.Logf("  🌐 VNet: %s (%s)", vnetName, vnetId)
			t.Logf("  🏠 AKS Subnet: %s", aksSubnetName)
			t.Logf("  🏷️ Resource ID: %s", uniqueId)
		}
	})
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Test Disk Enabled Setup
	suite.testDiskEnabledSetup(subscriptionID, testRegion)
}

func (suite *StagedDeploymentTestSuite) testDiskEnabledSetup(subscriptionID, testRegion string) {
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

func (suite *StagedDeploymentTestSuite) setupAKSStage(stage, stageDir, subscriptionID, region, nameSuffix, diskEnabled, vmSize string) {
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
	kubeConfigRaw := terraform.OutputMap(t, aksOptions, "kube_config")

	suite.NotEmpty(clusterName, "AKS cluster name should not be empty")
	suite.NotEmpty(kubeConfigRaw, "Kube config should not be empty")

	// Save AKS outputs for Materialize stage
	test_structure.SaveString(t, stageDirPath, "cluster_name", clusterName)
	test_structure.SaveString(t, stageDirPath, "cluster_endpoint", clusterEndpoint)
	test_structure.SaveString(t, stageDirPath, "workload_identity_client_id", workloadIdentityClientId)
	test_structure.SaveString(t, stageDirPath, "cluster_identity_principal_id", clusterIdentityPrincipalId)

	// Save kube config components separately for easier loading
	test_structure.SaveString(t, stageDirPath, "kube_config_client_certificate", kubeConfigRaw["client_certificate"])
	test_structure.SaveString(t, stageDirPath, "kube_config_client_key", kubeConfigRaw["client_key"])
	test_structure.SaveString(t, stageDirPath, "kube_config_cluster_ca_certificate", kubeConfigRaw["cluster_ca_certificate"])

	t.Logf("✅ AKS cluster created successfully:")
	t.Logf("  🏷️ Cluster Name: %s", clusterName)
	t.Logf("  🔗 Endpoint: %s", clusterEndpoint)
	t.Logf("  🆔 Workload Identity Client ID: %s", workloadIdentityClientId)
}

func (suite *StagedDeploymentTestSuite) setupDatabaseStage(stage, stageDir, subscriptionID, region, nameSuffix, diskEnabled string) {
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
	privateIP := terraform.Output(t, dbOptions, "private_ip")

	// Comprehensive validation
	suite.NotEmpty(serverName, "Database server name should not be empty")
	suite.NotEmpty(serverFQDN, "Database server FQDN should not be empty")
	suite.Equal(TestDBUsername, adminLogin, "Database username should match the configured value")
	suite.NotEmpty(adminPassword, "Database password should not be empty")

	// Save database outputs for future stages
	test_structure.SaveString(t, stageDirPath, "server_name", serverName)
	test_structure.SaveString(t, stageDirPath, "server_fqdn", serverFQDN)
	test_structure.SaveString(t, stageDirPath, "administrator_login", adminLogin)
	test_structure.SaveString(t, stageDirPath, "administrator_password", adminPassword)
	test_structure.SaveString(t, stageDirPath, "private_ip", privateIP)

	t.Logf("✅ Database created successfully:")
	t.Logf("  🔗 Server Name: %s", serverName)
	t.Logf("  🔗 FQDN: %s", serverFQDN)
	t.Logf("  👤 Username: %s", adminLogin)
	t.Logf("  🔒 Private IP: %s", privateIP)
}

func (suite *StagedDeploymentTestSuite) setupMaterializeStage(stage, stageDir, subscriptionID, region, nameSuffix, diskEnabled string) {
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
	aksStageDirFullPath := filepath.Join(suite.workingDir, utils.AKSDiskEnabledDir)
	clusterEndpoint := test_structure.LoadString(t, aksStageDirFullPath, "cluster_endpoint")
	clusterIdentityPrincipalId := test_structure.LoadString(t, aksStageDirFullPath, "cluster_identity_principal_id")

	// Load database data
	dbStageDirFullPath := filepath.Join(suite.workingDir, utils.DatabaseDiskEnabledDir)
	databaseHost := test_structure.LoadString(t, dbStageDirFullPath, "private_ip")
	databaseAdminLogin := test_structure.LoadString(t, dbStageDirFullPath, "administrator_login")
	databaseAdminPassword := test_structure.LoadString(t, dbStageDirFullPath, "administrator_password")

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

	materializeOptions := &terraform.Options{
		TerraformDir: materializePath,
		Vars: map[string]interface{}{
			"subscription_id":               subscriptionID,
			"location":                      region,
			"resource_group_name":           resourceGroupName,
			"prefix":                        fmt.Sprintf("%s%s", shortId, nameSuffix),
			"cluster_endpoint":              clusterEndpoint,
			"cluster_identity_principal_id": clusterIdentityPrincipalId,
			"subnets":                       []string{aksSubnetId},
			"kube_config":                   kubeConfig,
			"database_host":                 databaseHost,
			"database_name":                 TestDBName,
			"database_admin_user": map[string]interface{}{
				"name":     databaseAdminLogin,
				"password": databaseAdminPassword,
			},
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
			"install_cert_manager":           true,
			"cert_manager_namespace":         "cert-manager",
			"cert_manager_install_timeout":   300,
			"cert_manager_chart_version":     TestCertManagerVersion,
			"install_openebs":                diskEnabled == "true",
			"openebs_namespace":              "openebs",
			"openebs_version":                TestOpenEbsVersion,
			"materialize_instance_name":      TestMaterializeInstanceName,
			"materialize_instance_namespace": TestMaterializeInstanceNamespace,
			"install_materialize_operator":   true,
			"install_materialize_instance":   false, // Phase 1: operator only
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
	metadataBackendURL := terraform.Output(t, materializeOptions, "metadata_backend_url")
	persistBackendURL := terraform.Output(t, materializeOptions, "persist_backend_url")
	instanceInstalled := terraform.Output(t, materializeOptions, "instance_installed")
	instanceResourceId := terraform.Output(t, materializeOptions, "instance_resource_id")
	openebsInstalled := terraform.Output(t, materializeOptions, "openebs_installed")

	suite.Equal("true", instanceInstalled, "Materialize instance should be installed")
	suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")
	suite.NotEmpty(storageAccountName, "Storage account name should not be empty")
	suite.NotEmpty(metadataBackendURL, "Metadata backend URL should not be empty")
	suite.NotEmpty(persistBackendURL, "Persist backend URL should not be empty")

	if diskEnabled == "true" {
		suite.Equal("true", openebsInstalled, "OpenEBS should be installed if disk support is enabled")
	}

	t.Logf("✅ Phase 2: Materialize instance created successfully:")
	t.Logf("  🗄️ Storage Account: %s", storageAccountName)
	t.Logf("  🗄️ Metadata Backend URL: %s", metadataBackendURL)
	t.Logf("  🗄️ Persist Backend URL: %s", persistBackendURL)
	t.Logf("  🗄️ Instance Resource ID: %s", instanceResourceId)
	t.Logf("  🗄️ OpenEBS Installed: %s", openebsInstalled)

	test_structure.SaveString(t, stageDirFullPath, "storage_account_name", storageAccountName)
	test_structure.SaveString(t, stageDirFullPath, "metadata_backend_url", metadataBackendURL)
	test_structure.SaveString(t, stageDirFullPath, "persist_backend_url", persistBackendURL)
	test_structure.SaveString(t, stageDirFullPath, "instance_resource_id", instanceResourceId)
	test_structure.SaveString(t, stageDirFullPath, "openebs_installed", openebsInstalled)
}

func (suite *StagedDeploymentTestSuite) useExistingNetwork() {
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

// TestStagedDeploymentTestSuite runs the test suite
func TestStagedDeploymentTestSuite(t *testing.T) {
	suite.Run(t, new(StagedDeploymentTestSuite))
}
