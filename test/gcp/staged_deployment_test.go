package test

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/suite"
)

// StagedDeploymentSuite tests infrastructure deployment in stages with dependency management
type StagedDeploymentSuite struct {
	BaseTestSuite
	workingDir string
}

// SetupSuite runs once before all tests in the suite
func (suite *StagedDeploymentSuite) SetupSuite() {
	suite.SetupBaseSuite("StagedDeployment")
	// Working directory will be set dynamically based on uniqueId
	suite.workingDir = "" // Will be set in network stage
}

// TearDownSuite runs once after all tests in the suite
func (suite *StagedDeploymentSuite) TearDownSuite() {
	suite.TearDownBaseSuite()
}

// AfterTest runs after each individual test - handles cleanup stages
func (suite *StagedDeploymentSuite) AfterTest(suiteName, testName string) {
	t := suite.T()
	t.Logf("🧹 Starting cleanup stages for: %s", testName)

	// Cleanup stages (run in reverse order: database first, then network)
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

// TestNetworkAndDatabase tests network creation followed by database
func (suite *StagedDeploymentSuite) TestNetworkAndDatabase() {
	t := suite.T()

	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		// Generate unique ID for this infrastructure family
		uniqueId := generateGCPCompliantID()
		suite.workingDir = fmt.Sprintf("%s/%s", TestRunsDir, uniqueId)
		os.MkdirAll(suite.workingDir, 0755)
		t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
		t.Logf("📁 State directory: %s", suite.workingDir)

		projectID := os.Getenv("GOOGLE_PROJECT")

		networkOptions := &terraform.Options{
			TerraformDir: "../../gcp/examples/test-networking-basic",
			Vars: map[string]any{
				"project_id": projectID,
				"region":     TestRegion,
				"prefix":     fmt.Sprintf("test-%s", uniqueId),
			},
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, suite.workingDir, networkOptions)

		// Apply
		terraform.InitAndApply(t, networkOptions)

		// Save all networking outputs for subsequent stages
		networkName := terraform.Output(t, networkOptions, "network_name")
		networkId := terraform.Output(t, networkOptions, "network_id")
		subnetName := terraform.Output(t, networkOptions, "subnet_name")
		subnetId := terraform.Output(t, networkOptions, "subnet_id")
		routerName := terraform.Output(t, networkOptions, "router_name")
		natName := terraform.Output(t, networkOptions, "nat_name")
		privateVpcConnection := terraform.Output(t, networkOptions, "private_vpc_connection")

		// Save all outputs and resource IDs
		test_structure.SaveString(t, suite.workingDir, "network_name", networkName)
		test_structure.SaveString(t, suite.workingDir, "network_id", networkId)
		test_structure.SaveString(t, suite.workingDir, "subnet_name", subnetName)
		test_structure.SaveString(t, suite.workingDir, "subnet_id", subnetId)
		test_structure.SaveString(t, suite.workingDir, "router_name", routerName)
		test_structure.SaveString(t, suite.workingDir, "nat_name", natName)
		test_structure.SaveString(t, suite.workingDir, "private_vpc_connection", privateVpcConnection)
		test_structure.SaveString(t, suite.workingDir, "project_id", projectID)
		test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)

		t.Logf("✅ Network infrastructure created:")
		t.Logf("  🌐 Network: %s", networkName)
		t.Logf("  🏠 Subnet: %s", subnetName)
		t.Logf("  🔀 Router: %s", routerName)
		t.Logf("  🌍 NAT: %s", natName)
		t.Logf("  🏷️ Resource ID: %s", uniqueId)
	})
	if os.Getenv("SKIP_setup_network") != "" {
		// Find and load existing network state
		stateBaseDir := TestRunsDir
		
		// Check if state base directory exists
		if _, err := os.Stat(stateBaseDir); os.IsNotExist(err) {
			t.Fatal("❌ Cannot skip network creation: State directory does not exist. Run without SKIP_setup_network first.")
		}
		
		// Get the most recent state directory
		latestDirPath, err := GetLatestModifiedSubDir(stateBaseDir)
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

	// Stage 2: Database Setup
	test_structure.RunTestStage(t, "setup_database", func() {
		// Ensure workingDir is set (should be set by network stage)
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot create database: Working directory not set. Run network setup stage first.")
		}

		// Load saved network data with validation
		networkName := test_structure.LoadString(t, suite.workingDir, "network_name")
		networkId := test_structure.LoadString(t, suite.workingDir, "network_id")
		projectID := test_structure.LoadString(t, suite.workingDir, "project_id")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

		// Validate required network data exists
		if networkName == "" || networkId == "" || projectID == "" || resourceId == "" {
			t.Fatal("❌ Cannot create database: Missing network data. Run network setup stage first.")
		}

		t.Logf("🔗 Using infrastructure family: %s", resourceId)

		dbOptions := &terraform.Options{
			TerraformDir: "../../gcp/examples/test-database-basic",
			Vars: map[string]any{
				"project_id":        projectID,
				"region":            TestRegion,
				"prefix":            fmt.Sprintf("test-%s-db", resourceId),
				"network_id":        networkId,
				"database_password": "test-password-123!",
				"database_name":     "materialize-test",
				"user_name":         "materialize-test",
			},
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/database", dbOptions)

		// Apply
		terraform.InitAndApply(t, dbOptions)

		// Validate
		dbInstanceName := terraform.Output(t, dbOptions, "instance_name")
		suite.NotEmpty(dbInstanceName, "Database instance name should not be empty")

		t.Logf("✅ Database created: %s", dbInstanceName)
	})
}

// TestStagedDeploymentSuite runs the test suite
func TestStagedDeploymentSuite(t *testing.T) {
	suite.Run(t, new(StagedDeploymentSuite))
}
