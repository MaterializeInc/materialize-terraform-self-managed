package test

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/suite"
)

// StagedDeploymentTestSuite tests the full AWS infrastructure deployment in stages
type StagedDeploymentTestSuite struct {
	BaseTestSuite
	workingDir string
}

// SetupSuite initializes the test suite
func (suite *StagedDeploymentTestSuite) SetupSuite() {
	suite.SetupBaseSuite("AWS Staged Deployment")
	// Working directory will be set dynamically based on uniqueId
	suite.workingDir = "" // Will be set in network stage
}

// TearDownSuite cleans up the test suite
func (suite *StagedDeploymentTestSuite) TearDownSuite() {
	suite.TearDownBaseSuite()
}

// AfterTest runs after each individual test - handles cleanup stages
func (suite *StagedDeploymentTestSuite) AfterTest(suiteName, testName string) {
	t := suite.T()
	t.Logf("🧹 Starting cleanup stages for: %s", testName)

	// Cleanup stages (run in reverse order: Database, then network)
	test_structure.RunTestStage(t, "cleanup_database", func() {
		// Only cleanup if database was created in this test run
		if dbOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/database"); dbOptions != nil {
			t.Logf("🗑️ Cleaning up database...")
			terraform.Destroy(t, dbOptions)
			t.Logf("✅ Database cleanup completed")
		} else {
			t.Logf("♻️ No database to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_network", func() {
		// Cleanup network if it was created in this test run
		if networkOptions := test_structure.LoadTerraformOptions(t, suite.workingDir); networkOptions != nil {
			t.Logf("🗑️ Cleaning up network...")
			terraform.Destroy(t, networkOptions)
			t.Logf("✅ Network cleanup completed")

			// Remove entire state directory since network is the foundation
			t.Logf("🗂️ Removing state directory: %s", suite.workingDir)
			os.RemoveAll(suite.workingDir)
			t.Logf("✅ State directory cleanup completed")
		} else {
			t.Logf("♻️ No network to cleanup (was not created in this test)")
		}
	})
}

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → Database
func (suite *StagedDeploymentTestSuite) TestFullDeployment() {
	t := suite.T()

	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		// Generate unique ID for this infrastructure family
		uniqueId := generateAWSCompliantID()
		suite.workingDir = fmt.Sprintf("%s/%s", TestRunsDir, uniqueId)
		os.MkdirAll(suite.workingDir, 0755)
		t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
		t.Logf("📁 State directory: %s", suite.workingDir)

		// Set up networking example
		networkingPath := setupTestExample(t, uniqueId, "test-networking")

		networkOptions := &terraform.Options{
			TerraformDir: networkingPath,
			Vars: map[string]interface{}{
				"name_prefix":           fmt.Sprintf("%s-net", uniqueId),
				"vpc_cidr":              TestVPCCIDR,
				"availability_zones":    []string{TestAvailabilityZoneA, TestAvailabilityZoneB},
				"private_subnet_cidrs":  []string{TestPrivateSubnetCIDRA, TestPrivateSubnetCIDRB},
				"public_subnet_cidrs":   []string{TestPublicSubnetCIDRA, TestPublicSubnetCIDRB},
				"single_nat_gateway":    true,
				"create_vpc":            true,
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
	})

	// Stage 2: Database Setup
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
		databasePath := setupTestExample(t, resourceId, "test-database")

		dbOptions := &terraform.Options{
			TerraformDir: databasePath,
			Vars: map[string]interface{}{
				"name_prefix":              fmt.Sprintf("%s-db", resourceId),
				"vpc_id":                   vpcId,
				"database_subnet_ids":      privateSubnetIds,
				"postgres_version":         TestPostgreSQLVersion,
				"instance_class":           TestRDSInstanceClassSmall,
				"allocated_storage":        TestAllocatedStorageSmall,
				"max_allocated_storage":    TestMaxAllocatedStorageSmall,
				"multi_az":                 false,
				"database_name":            TestDBName,
				"database_username":        TestDBUsername,
				"database_password":        TestPassword,
				"maintenance_window":       TestMaintenanceWindow,
				"backup_window":            TestBackupWindow,
				"backup_retention_period":  TestBackupRetentionPeriod,
				"eks_security_group_id":        "sg-placeholder-eks",
				"eks_node_security_group_id":   "sg-placeholder-nodes",
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

		// Validate
		databaseEndpoint := terraform.Output(t, dbOptions, "database_endpoint")
		databasePort := terraform.Output(t, dbOptions, "database_port")
		suite.NotEmpty(databaseEndpoint, "Database endpoint should not be empty")
		suite.Equal("5432", databasePort, "Database port should be 5432")

		t.Logf("✅ Database created: %s:%s", databaseEndpoint, databasePort)
	})
}

// TestStagedDeploymentSuite runs the staged deployment test suite
func TestStagedDeploymentSuite(t *testing.T) {
	// Check required environment variables
	if os.Getenv("PROJECT_ROOT") == "" {
		t.Fatal("PROJECT_ROOT environment variable must be set")
	}

	if os.Getenv("AWS_REGION") == "" && os.Getenv("AWS_DEFAULT_REGION") == "" {
		t.Fatal("AWS_REGION or AWS_DEFAULT_REGION environment variable must be set")
	}

	// Run the test suite
	suite.Run(t, new(StagedDeploymentTestSuite))
}