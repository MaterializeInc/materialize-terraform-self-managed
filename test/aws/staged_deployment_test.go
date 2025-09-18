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

// StagedDeploymentTestSuite tests the full AWS infrastructure deployment in stages
type StagedDeploymentTestSuite struct {
	basesuite.BaseTestSuite
	workingDir string
}

// SetupSuite initializes the test suite
func (suite *StagedDeploymentTestSuite) SetupSuite() {
	configurations := config.GetCommonConfigurations()
	configurations = append(configurations, getRequiredAWSConfigurations()...)
	suite.SetupBaseSuite("AWS Staged Deployment", utils.AWS, configurations)
	// Working directory will be set dynamically based on uniqueId
	suite.workingDir = "" // Will be set in network stage
}

// TearDownSuite cleans up the test suite
func (suite *StagedDeploymentTestSuite) TearDownSuite() {
	t := suite.T()
	t.Logf("🧹 Starting cleanup stages for: %s", suite.SuiteName)
	suite.testDiskDisabledCleanup()

	suite.testDiskEnabledCleanup()

	test_structure.RunTestStage(t, "cleanup_network", func() {
		// Cleanup network if it was created in this test run
		if networkOptions := test_structure.LoadTerraformOptions(t, suite.workingDir); networkOptions != nil {
			t.Logf("🗑️ Cleaning up network...")
			// TODO: fix cleanup when Destroy errors out because Terraform init was not successful during Terraform InitAndApply
			terraform.Destroy(t, networkOptions)
			t.Logf("✅ Network cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId, utils.NetworkingDir)

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
	// Add specific cleanup tests for disk enabled setup here

	test_structure.RunTestStage(t, "cleanup_materialize_disk_enabled", func() {
		suite.cleanupStage("cleanup_materialize_disk_enabled", utils.MaterializeDiskEnabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_database_disk_enabled", func() {
		suite.cleanupStage("cleanup_database_disk_enabled", utils.DatabaseDiskEnabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_eks_disk_enabled", func() {
		suite.cleanupStage("cleanup_eks_disk_enabled", utils.EKSDiskEnabledDir)
	})

	t.Logf("✅ Disk Enabled Cleanup completed successfully")
}

func (suite *StagedDeploymentTestSuite) testDiskDisabledCleanup() {
	t := suite.T()

	t.Log("Running Disk Disabled Cleanup Tests")
	test_structure.RunTestStage(t, "cleanup_materialize_disk_disabled", func() {
		suite.cleanupStage("cleanup_materialize_disk_disabled", utils.MaterializeDiskDisabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_database_disk_disabled", func() {
		suite.cleanupStage("cleanup_database_disk_disabled", utils.DatabaseDiskDisabledDir)
	})

	test_structure.RunTestStage(t, "cleanup_eks_disk_disabled", func() {
		suite.cleanupStage("cleanup_eks_disk_disabled", utils.EKSDiskDisabledDir)
	})

	t.Logf("✅ Disk Disabled Cleanup completed successfully")
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
	helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId, stageDir)
}

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → (disk-enabled-setup) → (disk-disabled-setup)
func (suite *StagedDeploymentTestSuite) TestFullDeployment() {
	t := suite.T()
	awsRegion := os.Getenv("AWS_REGION")
	awsProfile := os.Getenv("AWS_PROFILE")
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
			// Generate unique ID for this infrastructure family
			uniqueId = generateAWSCompliantID()
			suite.workingDir = fmt.Sprintf("%s/%s", TestRunsDir, uniqueId)
			os.MkdirAll(suite.workingDir, 0755)
			t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
			t.Logf("📁 Test Stage Output directory: %s", suite.workingDir)
			// Save unique ID for subsequent stages
			test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)
		}
		// Set up networking example
		networkingPath := helpers.SetupTestWorkspace(t, utils.AWS, uniqueId, utils.NetworkingDir, utils.NetworkingDir)

		networkOptions := &terraform.Options{
			TerraformDir: networkingPath,
			Vars: map[string]interface{}{
				"profile":              awsProfile,
				"region":               awsRegion,
				"name_prefix":          fmt.Sprintf("%s-net", uniqueId),
				"vpc_cidr":             TestVPCCIDR,
				"availability_zones":   []string{TestAvailabilityZoneA, TestAvailabilityZoneB},
				"private_subnet_cidrs": []string{TestPrivateSubnetCIDRA, TestPrivateSubnetCIDRB},
				"public_subnet_cidrs":  []string{TestPublicSubnetCIDRA, TestPublicSubnetCIDRB},
				"single_nat_gateway":   true,
				"create_vpc":           true,
				"tags": map[string]string{
					"Environment": "test",
					"Project":     "materialize",
					"TestRun":     uniqueId,
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
		vpcId := terraform.Output(t, networkOptions, "vpc_id")
		privateSubnetIds := terraform.OutputList(t, networkOptions, "private_subnet_ids")
		publicSubnetIds := terraform.OutputList(t, networkOptions, "public_subnet_ids")

		// Save all outputs and resource IDs
		test_structure.SaveString(t, suite.workingDir, "vpc_id", vpcId)
		test_structure.SaveString(t, suite.workingDir, "private_subnet_ids", strings.Join(privateSubnetIds, ","))
		test_structure.SaveString(t, suite.workingDir, "public_subnet_ids", strings.Join(publicSubnetIds, ","))

		t.Logf("✅ Network infrastructure created:")
		t.Logf("  🌐 VPC: %s", vpcId)
		t.Logf("  🔒 Private Subnets: %v", privateSubnetIds)
		t.Logf("  🌍 Public Subnets: %v", publicSubnetIds)
		t.Logf("  🏷️ Resource ID: %s", uniqueId)

	})
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Test Disk Enabled Setup
	suite.testDiskEnabledSetup(awsProfile, awsRegion)

	// Test Disk Disabled setup
	suite.testDiskDisabledSetup(awsProfile, awsRegion)
}

func (suite *StagedDeploymentTestSuite) testDiskEnabledSetup(awsProfile, awsRegion string) {
	t := suite.T()
	t.Log("Running Disk Enabled Setup Tests")
	// Add specific tests for disk enabled setup here

	// Stage 2: EKS Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_eks_disk_enabled", func() {
		suite.setupEKSStage("setup_eks_disk_enabled", utils.EKSDiskEnabledDir, awsProfile, awsRegion,
			utils.DiskEnabledShortSuffix, true, TestEKSDiskEnabledInstanceType)
	})

	test_structure.RunTestStage(t, "setup_database_disk_enabled", func() {
		suite.setupDatabaseStage("setup_database_disk_enabled", utils.DatabaseDiskEnabledDir, awsProfile, awsRegion,
			utils.DiskEnabledShortSuffix, true)
	})

	// Stage 5: Materialize Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_materialize_disk_enabled", func() {
		suite.setupMaterializeStage("setup_materialize_disk_enabled", utils.MaterializeDiskEnabledDir, awsProfile, awsRegion,
			utils.DiskEnabledShortSuffix, true)
	})
	t.Logf("✅ Disk Enabled Setup completed successfully")
}

func (suite *StagedDeploymentTestSuite) testDiskDisabledSetup(awsProfile, awsRegion string) {
	t := suite.T()
	t.Log("Running Disk Disabled Setup Tests")
	test_structure.RunTestStage(t, "setup_eks_disk_disabled", func() {
		suite.setupEKSStage("setup_eks_disk_disabled", utils.EKSDiskDisabledDir, awsProfile, awsRegion,
			utils.DiskDisabledShortSuffix, false, TestEKSDiskDisabledInstanceType)
	})

	test_structure.RunTestStage(t, "setup_database_disk_disabled", func() {
		suite.setupDatabaseStage("setup_database_disk_disabled", utils.DatabaseDiskDisabledDir, awsProfile, awsRegion,
			utils.DiskDisabledShortSuffix, false)
	})
	test_structure.RunTestStage(t, "setup_materialize_disk_disabled", func() {
		suite.setupMaterializeStage("setup_materialize_disk_disabled", utils.MaterializeDiskDisabledDir, awsProfile, awsRegion,
			utils.DiskDisabledShortSuffix, false)
	})
	t.Logf("✅ Disk Disabled Setup completed successfully")
}

func (suite *StagedDeploymentTestSuite) setupEKSStage(stage, stageDir, profile, region, nameSuffix string, diskEnabled bool, instanceType string) {
	t := suite.T()
	t.Logf("🔧 Setting up EKS stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create EKS: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data
	vpcId := test_structure.LoadString(t, suite.workingDir, "vpc_id")
	privateSubnetIdsStr := test_structure.LoadString(t, suite.workingDir, "private_subnet_ids")
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

	// Parse private subnet IDs from comma-separated string
	privateSubnetIds := strings.Split(privateSubnetIdsStr, ",")

	// Validate required network data exists
	if vpcId == "" || len(privateSubnetIds) == 0 || privateSubnetIds[0] == "" || resourceId == "" {
		t.Fatal("❌ Cannot create EKS: Missing network data. Run network setup stage first.")
	}

	t.Logf("🔗 Using infrastructure family: %s", resourceId)

	// Set up EKS example with disk enabled
	eksPath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId, utils.EKSDir, stageDir)

	eksOptions := &terraform.Options{
		TerraformDir: eksPath,
		Vars: map[string]interface{}{
			"profile":                   profile,
			"region":                    region,
			"cluster_name":              fmt.Sprintf("%s%s", resourceId, nameSuffix),
			"cluster_version":           TestKubernetesVersion,
			"vpc_id":                    vpcId,
			"subnet_ids":                privateSubnetIds,
			"cluster_enabled_log_types": []string{"api", "audit"},
			"enable_cluster_creator_admin_permissions": true,
			"skip_node_group":                          false,
			"skip_aws_lbc":                             false,
			"min_nodes":                                1,
			"max_nodes":                                3,
			"desired_nodes":                            2,
			"instance_types":                           []string{instanceType},
			"capacity_type":                            "ON_DEMAND",
			"swap_enabled":                             diskEnabled,
			"iam_role_use_name_prefix":                 false,
			"node_labels": map[string]string{
				"Environment":            "test",
				"Project":                "materialize",
				"materialize.cloud/disk": strconv.FormatBool(diskEnabled),
			},
			"tags": map[string]string{
				"Environment": "test",
				"Project":     "materialize",
				"TestRun":     resourceId,
				"DiskEnabled": strconv.FormatBool(diskEnabled),
			},
		},
		RetryableTerraformErrors: map[string]string{
			"RequestError":              "Request failed",
			"InvalidParameterException": "EKS service error",
		},
		MaxRetries:         TestMaxRetries,
		TimeBetweenRetries: TestRetryDelay,
		NoColor:            true,
	}

	// Save terraform options for cleanup
	stageDirPath := filepath.Join(suite.workingDir, stageDir)
	test_structure.SaveTerraformOptions(t, stageDirPath, eksOptions)

	// Apply
	terraform.InitAndApply(t, eksOptions)

	// Save EKS outputs for subsequent stages
	clusterName := terraform.Output(t, eksOptions, "cluster_name")
	clusterEndpoint := terraform.Output(t, eksOptions, "cluster_endpoint")
	clusterSecurityGroupId := terraform.Output(t, eksOptions, "cluster_security_group_id")
	nodeSecurityGroupId := terraform.Output(t, eksOptions, "node_security_group_id")
	oidcProviderArn := terraform.Output(t, eksOptions, "oidc_provider_arn")
	clusterServiceCIDR := terraform.Output(t, eksOptions, "cluster_service_cidr")
	clusterOidcIssuerUrl := terraform.Output(t, eksOptions, "cluster_oidc_issuer_url")
	clusterCertificateAuthorityData := terraform.Output(t, eksOptions, "cluster_certificate_authority_data")

	// Validate outputs
	suite.NotEmpty(clusterName, "Cluster name should not be empty")
	suite.Contains(clusterName, resourceId, "Cluster name should contain resource ID")
	suite.Contains(clusterEndpoint, "eks.amazonaws.com", "Cluster endpoint should be valid EKS endpoint")
	suite.NotEmpty(clusterSecurityGroupId, "Cluster security group ID should not be empty")
	suite.NotEmpty(nodeSecurityGroupId, "Node security group ID should not be empty")
	suite.NotEmpty(oidcProviderArn, "OIDC provider ARN should not be empty")
	suite.NotEmpty(clusterServiceCIDR, "Cluster service CIDR should not be empty")
	suite.NotEmpty(clusterOidcIssuerUrl, "Cluster OIDC issuer URL should not be empty")
	suite.NotEmpty(clusterCertificateAuthorityData, "Cluster certificate authority data should not be empty")

	// Save all outputs
	test_structure.SaveString(t, stageDirPath, "cluster_name", clusterName)
	test_structure.SaveString(t, stageDirPath, "cluster_endpoint", clusterEndpoint)
	test_structure.SaveString(t, stageDirPath, "cluster_security_group_id", clusterSecurityGroupId)
	test_structure.SaveString(t, stageDirPath, "node_security_group_id", nodeSecurityGroupId)
	test_structure.SaveString(t, stageDirPath, "oidc_provider_arn", oidcProviderArn)
	test_structure.SaveString(t, stageDirPath, "cluster_oidc_issuer_url", clusterOidcIssuerUrl)
	test_structure.SaveString(t, stageDirPath, "cluster_service_cidr", clusterServiceCIDR)
	test_structure.SaveString(t, stageDirPath, "cluster_certificate_authority_data", clusterCertificateAuthorityData)

	// Save generic security group IDs for database stage
	test_structure.SaveString(t, stageDirPath, "cluster_security_group_id", clusterSecurityGroupId)
	test_structure.SaveString(t, stageDirPath, "node_security_group_id", nodeSecurityGroupId)

	// TODO add checks to ensure disk setup is enabled/disabled
	// use vgs/ pvs commands and verify the output

	t.Logf("✅ EKS cluster (disk-enabled: %t) created successfully:", diskEnabled)
	t.Logf("  📛 Cluster Name: %s", clusterName)
	t.Logf("  🔗 Endpoint: %s", clusterEndpoint)
	t.Logf("  🔒 Cluster Security Group: %s", clusterSecurityGroupId)
	t.Logf("  🔒 Node Security Group: %s", nodeSecurityGroupId)
	t.Logf("  🆔 OIDC Provider: %s", oidcProviderArn)
	t.Logf("  💾 Disk Enabled: %t", diskEnabled)
	t.Logf("  🌐 Cluster Service CIDR: %s", clusterServiceCIDR)
	t.Logf("  🌐 Cluster OIDC Issuer URL: %s", clusterOidcIssuerUrl)
	t.Logf("  📜 Cluster Certificate Authority Data: %s", clusterCertificateAuthorityData)

}

func (suite *StagedDeploymentTestSuite) setupDatabaseStage(stage, stageDir, profile, region, nameSuffix string, diskEnabled bool) {
	t := suite.T()

	t.Logf("Running Database Setup Stage: %s", stage)
	// Ensure workingDir is set (should be set by network stage)
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create database: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data with validation
	vpcId := test_structure.LoadString(t, suite.workingDir, "vpc_id")
	privateSubnetIdsStr := test_structure.LoadString(t, suite.workingDir, "private_subnet_ids")
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

	// Parse private subnet IDs from comma-separated string
	privateSubnetIds := strings.Split(privateSubnetIdsStr, ",")

	// Validate required network data exists
	if vpcId == "" || len(privateSubnetIds) == 0 || privateSubnetIds[0] == "" || resourceId == "" {
		t.Fatal("❌ Cannot create database: Missing network data. Run network setup stage first.")
	}

	// create a list of EKS clusters with their security group IDs
	eksStageDir := utils.EKSDiskDisabledDir
	if diskEnabled {
		eksStageDir = utils.EKSDiskEnabledDir
	}

	eksStageDirFullPath := filepath.Join(suite.workingDir, eksStageDir)

	_, err := os.Stat(eksStageDirFullPath)
	if err != nil {
		t.Fatalf("❌ Error checking %s output directory: %v",
			eksStageDirFullPath, err)
	}

	t.Logf("🔗 Using EKS stage directory: %s", eksStageDirFullPath)

	// Load EKS cluster security group IDs
	eksSecurityGroupId := test_structure.LoadString(t, eksStageDirFullPath, "cluster_security_group_id")
	nodeSecurityGroupId := test_structure.LoadString(t, eksStageDirFullPath, "node_security_group_id")
	clusterName := test_structure.LoadString(t, eksStageDirFullPath, "cluster_name")
	if eksSecurityGroupId == "" || nodeSecurityGroupId == "" {
		t.Fatal("❌ Cannot create database: Missing EKS cluster security group IDs. Ensure EKS cluster is created before the database stage.")
	}
	t.Logf("🔗 EKS cluster (disk-enabled: %t) security group IDs loaded for database access", diskEnabled)

	t.Logf("🔗 Using infrastructure family: %s", resourceId)

	// Set up database example
	databasePath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId, utils.DataBaseDir, stageDir)

	dbOptions := &terraform.Options{
		TerraformDir: databasePath,
		Vars: map[string]interface{}{
			"profile":                 profile,
			"region":                  region,
			"name_prefix":             fmt.Sprintf("%s%s", resourceId, nameSuffix),
			"vpc_id":                  vpcId,
			"database_subnet_ids":     privateSubnetIds,
			"postgres_version":        TestPostgreSQLVersion,
			"instance_class":          TestRDSInstanceClassSmall,
			"allocated_storage":       TestAllocatedStorageSmall,
			"max_allocated_storage":   TestMaxAllocatedStorageSmall,
			"multi_az":                false,
			"database_name":           TestDBName,
			"database_username":       TestDBUsername,
			"database_password":       TestPassword,
			"maintenance_window":      TestMaintenanceWindow,
			"backup_window":           TestBackupWindow,
			"backup_retention_period": TestBackupRetentionPeriod,
			// Load EKS security group IDs
			"cluster_name":              clusterName,
			"cluster_security_group_id": eksSecurityGroupId,
			"node_security_group_id":    nodeSecurityGroupId,
			"tags": map[string]string{
				"Environment": "test",
				"Project":     "materialize",
				"TestRun":     resourceId,
				"DiskEnabled": strconv.FormatBool(diskEnabled),
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
	databaseEndpoint := terraform.Output(t, dbOptions, "database_endpoint")
	databasePort := terraform.Output(t, dbOptions, "database_port")
	databaseName := terraform.Output(t, dbOptions, "database_name")
	databaseUsername := terraform.Output(t, dbOptions, "database_username")
	databaseIdentifier := terraform.Output(t, dbOptions, "database_identifier")

	// Comprehensive validation
	suite.NotEmpty(databaseEndpoint, "Database endpoint should not be empty")
	suite.Contains(databaseEndpoint, ".rds.amazonaws.com", "Database endpoint should be a valid RDS endpoint")
	suite.Equal("5432", databasePort, "Database port should be 5432")
	suite.Equal(TestDBName, databaseName, "Database name should match the configured value")
	suite.Equal(TestDBUsername, databaseUsername, "Database username should match the configured value")
	suite.Contains(databaseIdentifier, resourceId, "Database identifier should contain the resource ID")

	// Save database outputs for future stages
	test_structure.SaveString(t, stageDirPath, "database_endpoint", databaseEndpoint)
	test_structure.SaveString(t, stageDirPath, "database_port", databasePort)
	test_structure.SaveString(t, stageDirPath, "database_name", databaseName)
	test_structure.SaveString(t, stageDirPath, "database_identifier", databaseIdentifier)
	test_structure.SaveString(t, stageDirPath, "database_username", databaseUsername)

	t.Logf("✅ Database created successfully:")
	t.Logf("  🔗 Endpoint: %s:%s", databaseEndpoint, databasePort)
	t.Logf("  📛 Database Name: %s", databaseName)
	t.Logf("  👤 Username: %s", databaseUsername)
	t.Logf("  🏷️ Identifier: %s", databaseIdentifier)

	// TODO add checks to ensure database is created and accessible

}

func (suite *StagedDeploymentTestSuite) setupMaterializeStage(stage, stageDir, profile, region, nameSuffix string, diskEnabled bool) {
	t := suite.T()
	t.Logf("🔧 Setting up Materialize stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create Materialize: Working directory not set. Run network setup stage first.")
	}

	eksStageDir := utils.EKSDiskDisabledDir
	if diskEnabled {
		eksStageDir = utils.EKSDiskEnabledDir
	}
	eksStageDirFullPath := filepath.Join(suite.workingDir, eksStageDir)
	// Load saved EKS cluster data
	clusterName := test_structure.LoadString(t, eksStageDirFullPath, "cluster_name")
	clusterEndpoint := test_structure.LoadString(t, eksStageDirFullPath, "cluster_endpoint")
	clusterCertificateAuthorityData := test_structure.LoadString(t, eksStageDirFullPath, "cluster_certificate_authority_data")
	oidcProviderArn := test_structure.LoadString(t, eksStageDirFullPath, "oidc_provider_arn")
	clusterOidcIssuerUrl := test_structure.LoadString(t, eksStageDirFullPath, "cluster_oidc_issuer_url")
	resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

	if clusterName == "" || clusterEndpoint == "" || oidcProviderArn == "" || clusterCertificateAuthorityData == "" || clusterOidcIssuerUrl == "" {
		t.Fatal("❌ Cannot create Materialize: Missing EKS  cluster data. Run EKS setup stage first.")
	}

	// Load VPC ID and private subnet IDs
	vpcId := test_structure.LoadString(t, suite.workingDir, "vpc_id")
	privateSubnetIdsStr := test_structure.LoadString(t, suite.workingDir, "private_subnet_ids")
	privateSubnetIds := strings.Split(privateSubnetIdsStr, ",")
	if vpcId == "" || len(privateSubnetIds) == 0 {
		t.Fatal("❌ Cannot create Materialize: Missing VPC or private subnet IDs. Run network setup stage first.")
	}

	databaseStageDir := utils.DatabaseDiskDisabledDir
	if diskEnabled {
		databaseStageDir = utils.DatabaseDiskEnabledDir
	}
	databaseStageDirFullPath := filepath.Join(suite.workingDir, databaseStageDir)
	// Load database details
	databaseEndpoint := test_structure.LoadString(t, databaseStageDirFullPath, "database_endpoint")
	databaseName := test_structure.LoadString(t, databaseStageDirFullPath, "database_name")
	databaseUsername := test_structure.LoadString(t, databaseStageDirFullPath, "database_username")

	if databaseEndpoint == "" || databaseName == "" || databaseUsername == "" {
		t.Fatal("❌ Cannot create Materialize: Missing database details. Run database setup stage first.")
	}

	t.Logf("🔗 Using EKS cluster %s where disk-enabled : %t", clusterName, diskEnabled)

	// Set up Materialize example with disk enabled
	materializePath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId, utils.MaterializeDir, stageDir)
	expectedInstanceNamespace := fmt.Sprintf("mz-instance-%s", nameSuffix)
	expectedOperatorNamespace := fmt.Sprintf("mz-operator-%s", nameSuffix)
	expectedCertManagerNamespace := fmt.Sprintf("cert-manager-%s", nameSuffix)
	enableDiskSupport := diskEnabled
	materializeOptions := &terraform.Options{
		TerraformDir: materializePath,
		Vars: map[string]interface{}{
			"profile": profile,
			"region":  region,

			// vpc and subnet details
			"vpc_id":     vpcId,
			"subnet_ids": privateSubnetIds,

			// Cluster details
			"cluster_name":                       clusterName,
			"cluster_endpoint":                   clusterEndpoint,
			"cluster_certificate_authority_data": clusterCertificateAuthorityData,
			"oidc_provider_arn":                  oidcProviderArn,
			"cluster_oidc_issuer_url":            clusterOidcIssuerUrl,

			// S3 details
			"bucket_lifecycle_rules":   []interface{}{},
			"bucket_force_destroy":     true,
			"enable_bucket_versioning": false,
			"enable_bucket_encryption": false,

			// Cert Manager details
			"install_cert_manager":         true,
			"cert_manager_install_timeout": 600,
			"cert_manager_chart_version":   TestCertManagerVersion,
			"cert_manager_namespace":       expectedCertManagerNamespace,

			// Database details
			"database_username": databaseUsername,
			"database_password": TestPassword,
			"database_endpoint": databaseEndpoint,
			"database_name":     databaseName,

			// Disk setup details
			"swap_enabled": enableDiskSupport,

			// Operator details
			"operator_namespace": expectedOperatorNamespace,

			// Materialize instance details
			"install_materialize_instance":      false,
			"instance_name":                     fmt.Sprintf("%s-%s", resourceId, nameSuffix),
			"name_prefix":                       fmt.Sprintf("%s-%s", resourceId, nameSuffix),
			"instance_namespace":                expectedInstanceNamespace,
			"external_login_password_mz_system": TestPassword,

			// NLB details
			"enable_cross_zone_load_balancing": true,

			// Tags
			"tags": map[string]string{
				"Environment": "test",
				"Project":     "materialize",
				"TestRun":     resourceId,
				"DiskEnabled": strconv.FormatBool(diskEnabled),
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
	stageDirFullPath := filepath.Join(suite.workingDir, stageDir)
	test_structure.SaveTerraformOptions(t, stageDirFullPath, materializeOptions)

	// Apply
	terraform.InitAndApply(t, materializeOptions)

	t.Logf("✅ Phase 1: Materialize operator installed on cluster where disk-enabled: %t ", diskEnabled)

	// Phase 2: Update variables for instance deployment
	materializeOptions.Vars["install_materialize_instance"] = true

	// Phase 2: Apply with instance enabled
	terraform.Apply(t, materializeOptions)

	// Save Materialize outputs for subsequent stages
	s3BucketName := terraform.Output(t, materializeOptions, "s3_bucket_name")
	metadataBackendURL := terraform.Output(t, materializeOptions, "metadata_backend_url")
	persistBackendURL := terraform.Output(t, materializeOptions, "persist_backend_url")
	materializeS3RoleArn := terraform.Output(t, materializeOptions, "materialize_s3_role_arn")
	nlbDetails := terraform.OutputMap(t, materializeOptions, "nlb_details")
	nlbArn := nlbDetails["arn"]
	nlbDNSName := nlbDetails["dns_name"]
	instanceInstalled := terraform.Output(t, materializeOptions, "instance_installed")
	instanceResourceId := terraform.Output(t, materializeOptions, "instance_resource_id")
	clusterIssuerName := terraform.Output(t, materializeOptions, "cluster_issuer_name")
	operatorNamespace := terraform.Output(t, materializeOptions, "operator_namespace")

	suite.Equal("true", instanceInstalled, "Materialize instance should be installed")
	suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")
	suite.NotEmpty(s3BucketName, "S3 bucket name should not be empty")
	suite.NotEmpty(metadataBackendURL, "Metadata backend URL should not be empty")
	suite.NotEmpty(persistBackendURL, "Persist backend URL should not be empty")
	suite.NotEmpty(materializeS3RoleArn, "Materialize S3 role ARN should not be empty")
	suite.NotEmpty(nlbArn, "NLB ARN should not be empty")
	suite.NotEmpty(nlbDNSName, "NLB DNS name should not	 be empty")
	suite.NotEmpty(clusterIssuerName, "Cluster issuer name should not be empty")
	suite.Equalf(expectedOperatorNamespace, operatorNamespace, "Operator namespace equal %s", expectedOperatorNamespace)

	t.Logf("✅ Phase 2: Materialize instance created successfully:")
	//if enableDiskSupport {
	//	// TODO verify the instance has swap allowed in its cgroup
	//}

	test_structure.SaveString(t, stageDirFullPath, "s3_bucket_name", s3BucketName)
	test_structure.SaveString(t, stageDirFullPath, "metadata_backend_url", metadataBackendURL)
	test_structure.SaveString(t, stageDirFullPath, "persist_backend_url", persistBackendURL)
	test_structure.SaveString(t, stageDirFullPath, "materialize_s3_role_arn", materializeS3RoleArn)
	test_structure.SaveString(t, stageDirFullPath, "nlb_arn", nlbArn)
	test_structure.SaveString(t, stageDirFullPath, "nlb_dns_name", nlbDNSName)
	test_structure.SaveString(t, stageDirFullPath, "instance_resource_id", instanceResourceId)
	test_structure.SaveString(t, stageDirFullPath, "cluster_issuer_name", clusterIssuerName)
	test_structure.SaveString(t, stageDirFullPath, "operator_namespace", operatorNamespace)

	t.Logf("  🗄️ S3 Bucket: %s", s3BucketName)
	t.Logf("  🗄️ Metadata Backend URL: %s", metadataBackendURL)
	t.Logf("  🗄️ Persist Backend URL: %s", persistBackendURL)
	t.Logf("  🗄️ Materialize S3 Role ARN: %s", materializeS3RoleArn)
	t.Logf("  🗄️ NLB ARN: %s", nlbArn)
	t.Logf("  🗄️ NLB DNS Name: %s", nlbDNSName)
	t.Logf("  🗄️ Instance Resource ID: %s", instanceResourceId)
	t.Logf("  🗄️ Cluster Issuer Name: %s", clusterIssuerName)
	t.Logf("  🗄️ Operator Namespace: %s", operatorNamespace)
	t.Logf("  🗄️ Instance Installed: %s", instanceInstalled)
}

func (suite *StagedDeploymentTestSuite) useExistingNetwork() {
	t := suite.T()
	lastRunDir, err := dir.GetLastRunTestStageDir(TestRunsDir)
	if err != nil {
		t.Fatalf("Unable to use existing network %v", err)
	}
	// Use the full path returned by the helper
	suite.workingDir = lastRunDir
	latestDir := filepath.Base(lastRunDir)

	// Load vpc id using test_structure (handles .test-data path internally)
	vpcID := test_structure.LoadString(t, suite.workingDir, "vpc_id")
	if vpcID == "" {
		t.Fatalf("❌ Cannot skip network creation: VPC Id is empty in stage output directory %s", latestDir)
	}

	t.Logf("♻️ Skipping network creation, using existing: %s (ID: %s)", vpcID, latestDir)
}

// TestStagedDeploymentSuite runs the staged deployment test suite
func TestStagedDeploymentSuite(t *testing.T) {
	// Run the test suite
	suite.Run(t, new(StagedDeploymentTestSuite))
}
