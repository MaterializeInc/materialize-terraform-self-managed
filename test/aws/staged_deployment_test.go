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

	// Cleanup stages (run in reverse order: Database, EKS clusters, then network)
	test_structure.RunTestStage(t, "cleanup_database", func() {
		// Only cleanup if database was created in this test run
		if dbOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/database"); dbOptions != nil {
			t.Logf("🗑️ Cleaning up database...")
			terraform.Destroy(t, dbOptions)
			t.Logf("✅ Database cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId, utils.DataBaseDir)
		} else {
			t.Logf("♻️ No database to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_eks_disk_disabled", func() {
		// Cleanup EKS disk-disabled cluster if it was created in this test run
		if eksOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/eks-disk-disabled"); eksOptions != nil {
			t.Logf("🗑️ Cleaning up EKS cluster (disk-disabled)...")
			terraform.Destroy(t, eksOptions)
			t.Logf("✅ EKS cluster (disk-disabled) cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId+"-disk-disabled", "test-eks")
		} else {
			t.Logf("♻️ No EKS cluster (disk-disabled) to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_eks_disk_enabled", func() {
		// Cleanup EKS disk-enabled cluster if it was created in this test run
		if eksOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/eks-disk-enabled"); eksOptions != nil {
			t.Logf("🗑️ Cleaning up EKS cluster (disk-enabled)...")
			terraform.Destroy(t, eksOptions)
			t.Logf("✅ EKS cluster (disk-enabled) cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId+"-disk-enabled", "test-eks")
		} else {
			t.Logf("♻️ No EKS cluster (disk-enabled) to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_network", func() {
		// Cleanup network if it was created in this test run
		if networkOptions := test_structure.LoadTerraformOptions(t, suite.workingDir); networkOptions != nil {
			t.Logf("🗑️ Cleaning up network...")
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

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → EKS (disk-enabled) → EKS (disk-disabled) → Database
func (suite *StagedDeploymentTestSuite) TestFullDeployment() {
	t := suite.T()

	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		// Generate unique ID for this infrastructure family
		if os.Getenv("USE_EXISTING_NETWORK") != "" {
			suite.useExistingNetwork()
		} else {
			uniqueId := generateAWSCompliantID()
			suite.workingDir = fmt.Sprintf("%s/%s", TestRunsDir, uniqueId)
			os.MkdirAll(suite.workingDir, 0755)
			t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
			t.Logf("📁 Test Stage Output directory: %s", suite.workingDir)

			// Set up networking example
			networkingPath := helpers.SetupTestWorkspace(t, utils.AWS, uniqueId, utils.NetworkingDir)

			networkOptions := &terraform.Options{
				TerraformDir: networkingPath,
				Vars: map[string]interface{}{
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
			test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)
			test_structure.SaveString(t, suite.workingDir, "private_subnet_ids", strings.Join(privateSubnetIds, ","))
			test_structure.SaveString(t, suite.workingDir, "public_subnet_ids", strings.Join(publicSubnetIds, ","))

			t.Logf("✅ Network infrastructure created:")
			t.Logf("  🌐 VPC: %s", vpcId)
			t.Logf("  🔒 Private Subnets: %v", privateSubnetIds)
			t.Logf("  🌍 Public Subnets: %v", publicSubnetIds)
			t.Logf("  🏷️ Resource ID: %s", uniqueId)
		}
	})
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Stage 2: EKS Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_eks_disk_enabled", func() {
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
		eksPath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId+"-disk-enabled", "test-eks")

		eksOptions := &terraform.Options{
			TerraformDir: eksPath,
			Vars: map[string]interface{}{
				"region":                    TestRegion,
				"cluster_name":              fmt.Sprintf("%s-eks-disk", resourceId),
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
				"instance_types":                           []string{TestEKSDiskEnabledInstanceType},
				"capacity_type":                            "ON_DEMAND",
				"disk_setup_enabled":                       true,
				"iam_role_use_name_prefix":                 false,
				"node_labels": map[string]string{
					"Environment":            "test",
					"Project":                "materialize",
					"materialize.cloud/disk": "true",
					"workload":               "materialize-instance",
				},
				"tags": map[string]string{
					"Environment": "test",
					"Project":     "materialize",
					"TestRun":     resourceId,
					"DiskEnabled": "true",
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
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/eks-disk-enabled", eksOptions)

		// Apply
		terraform.InitAndApply(t, eksOptions)

		// Save EKS outputs for subsequent stages
		clusterName := terraform.Output(t, eksOptions, "cluster_name")
		clusterEndpoint := terraform.Output(t, eksOptions, "cluster_endpoint")
		clusterSecurityGroupId := terraform.Output(t, eksOptions, "cluster_security_group_id")
		nodeSecurityGroupId := terraform.Output(t, eksOptions, "node_security_group_id")
		oidcProviderArn := terraform.Output(t, eksOptions, "oidc_provider_arn")
		clusterServiceCIDR := terraform.Output(t, eksOptions, "cluster_service_cidr")

		// Save all outputs with disk-enabled suffix
		test_structure.SaveString(t, suite.workingDir, "cluster_name_disk_enabled", clusterName)
		test_structure.SaveString(t, suite.workingDir, "cluster_endpoint_disk_enabled", clusterEndpoint)
		test_structure.SaveString(t, suite.workingDir, "cluster_security_group_id_disk_enabled", clusterSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir, "node_security_group_id_disk_enabled", nodeSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir, "oidc_provider_arn_disk_enabled", oidcProviderArn)
		test_structure.SaveString(t, suite.workingDir, "cluster_service_cidr_disk_enabled", clusterServiceCIDR)

		// Save generic security group IDs for database stage
		test_structure.SaveString(t, suite.workingDir, "cluster_security_group_id", clusterSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir, "node_security_group_id", nodeSecurityGroupId)

		// Validate outputs
		suite.NotEmpty(clusterName, "Cluster name should not be empty")
		suite.Contains(clusterName, resourceId, "Cluster name should contain resource ID")
		suite.Contains(clusterEndpoint, "eks.amazonaws.com", "Cluster endpoint should be valid EKS endpoint")
		suite.NotEmpty(clusterSecurityGroupId, "Cluster security group ID should not be empty")
		suite.NotEmpty(nodeSecurityGroupId, "Node security group ID should not be empty")
		suite.NotEmpty(oidcProviderArn, "OIDC provider ARN should not be empty")

		t.Logf("✅ EKS cluster (disk-enabled) created successfully:")
		t.Logf("  📛 Cluster Name: %s", clusterName)
		t.Logf("  🔗 Endpoint: %s", clusterEndpoint)
		t.Logf("  🔒 Cluster Security Group: %s", clusterSecurityGroupId)
		t.Logf("  🔒 Node Security Group: %s", nodeSecurityGroupId)
		t.Logf("  🆔 OIDC Provider: %s", oidcProviderArn)
		t.Logf("  💾 Disk Enabled: true")
	})

	// Stage 3: EKS Setup (Disk Disabled)
	test_structure.RunTestStage(t, "setup_eks_disk_disabled", func() {
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

		// Set up EKS example with disk disabled
		eksPath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId+"-disk-disabled", "test-eks")

		eksOptions := &terraform.Options{
			TerraformDir: eksPath,
			Vars: map[string]interface{}{
				"region":                    TestRegion,
				"cluster_name":              fmt.Sprintf("%s-eks-nodisk", resourceId),
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
				"instance_types":                           []string{TestEKSDiskDisabledInstanceType},
				"capacity_type":                            "ON_DEMAND",
				"disk_setup_enabled":                       false,
				"iam_role_use_name_prefix":                 false,
				"node_labels": map[string]string{
					"Environment":            "test",
					"Project":                "materialize",
					"materialize.cloud/disk": "false",
					"workload":               "materialize-instance",
				},
				"tags": map[string]string{
					"Environment": "test",
					"Project":     "materialize",
					"TestRun":     resourceId,
					"DiskEnabled": "false",
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
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/eks-disk-disabled", eksOptions)

		// Apply
		terraform.InitAndApply(t, eksOptions)

		// Save EKS outputs for subsequent stages
		clusterName := terraform.Output(t, eksOptions, "cluster_name")
		clusterEndpoint := terraform.Output(t, eksOptions, "cluster_endpoint")
		clusterSecurityGroupId := terraform.Output(t, eksOptions, "cluster_security_group_id")
		nodeSecurityGroupId := terraform.Output(t, eksOptions, "node_security_group_id")
		oidcProviderArn := terraform.Output(t, eksOptions, "oidc_provider_arn")
		clusterServiceCIDR := terraform.Output(t, eksOptions, "cluster_service_cidr")

		// Save all outputs with disk-disabled suffix
		test_structure.SaveString(t, suite.workingDir, "cluster_name_disk_disabled", clusterName)
		test_structure.SaveString(t, suite.workingDir, "cluster_endpoint_disk_disabled", clusterEndpoint)
		test_structure.SaveString(t, suite.workingDir, "cluster_security_group_id_disk_disabled", clusterSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir, "node_security_group_id_disk_disabled", nodeSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir, "oidc_provider_arn_disk_disabled", oidcProviderArn)
		test_structure.SaveString(t, suite.workingDir, "cluster_service_cidr_disk_disabled", clusterServiceCIDR)

		// Validate outputs
		suite.NotEmpty(clusterName, "Cluster name should not be empty")
		suite.Contains(clusterName, resourceId, "Cluster name should contain resource ID")
		suite.Contains(clusterEndpoint, "eks.amazonaws.com", "Cluster endpoint should be valid EKS endpoint")
		suite.NotEmpty(clusterSecurityGroupId, "Cluster security group ID should not be empty")
		suite.NotEmpty(nodeSecurityGroupId, "Node security group ID should not be empty")
		suite.NotEmpty(oidcProviderArn, "OIDC provider ARN should not be empty")

		t.Logf("✅ EKS cluster (disk-disabled) created successfully:")
		t.Logf("  📛 Cluster Name: %s", clusterName)
		t.Logf("  🔗 Endpoint: %s", clusterEndpoint)
		t.Logf("  🔒 Cluster Security Group: %s", clusterSecurityGroupId)
		t.Logf("  🔒 Node Security Group: %s", nodeSecurityGroupId)
		t.Logf("  🆔 OIDC Provider: %s", oidcProviderArn)
		t.Logf("  💾 Disk Enabled: false")
	})

	// Stage 4: Database Setup
	test_structure.RunTestStage(t, "setup_database", func() {
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

		t.Logf("🔗 Using infrastructure family: %s", resourceId)

		// Set up database example
		databasePath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId, utils.DataBaseDir)

		dbOptions := &terraform.Options{
			TerraformDir: databasePath,
			Vars: map[string]interface{}{
				"name_prefix":             fmt.Sprintf("%s-db", resourceId),
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
				// Load EKS security group IDs if available (using disk-enabled cluster for database access)
				"eks_security_group_id":      test_structure.LoadString(t, suite.workingDir, "cluster_security_group_id"),
				"eks_node_security_group_id": test_structure.LoadString(t, suite.workingDir, "node_security_group_id"),
				"tags": map[string]string{
					"Environment": "test",
					"Project":     "materialize",
					"TestRun":     resourceId,
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
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/database", dbOptions)

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
		test_structure.SaveString(t, suite.workingDir, "database_endpoint", databaseEndpoint)
		test_structure.SaveString(t, suite.workingDir, "database_port", databasePort)
		test_structure.SaveString(t, suite.workingDir, "database_name", databaseName)
		test_structure.SaveString(t, suite.workingDir, "database_identifier", databaseIdentifier)

		t.Logf("✅ Database created successfully:")
		t.Logf("  🔗 Endpoint: %s:%s", databaseEndpoint, databasePort)
		t.Logf("  📛 Database Name: %s", databaseName)
		t.Logf("  👤 Username: %s", databaseUsername)
		t.Logf("  🏷️ Identifier: %s", databaseIdentifier)
	})
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
