package test

import (
	"fmt"
	"os"
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

	// Cleanup stages (run in reverse order: GKE first, then database, then network)
	test_structure.RunTestStage(t, "cleanup_gke_disk_enabled", func() {
		// Only cleanup if GKE disk-enabled was created in this test run
		if gkeOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/gke-disk-enabled"); gkeOptions != nil {
			t.Logf("🗑️ Cleaning up GKE with disk enabled...")
			terraform.Destroy(t, gkeOptions)
			t.Logf("✅ GKE disk-enabled cleanup completed")
		} else {
			t.Logf("♻️ No GKE disk-enabled to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_gke_disk_disabled", func() {
		// Only cleanup if GKE disk-disabled was created in this test run
		if gkeOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/gke-disk-disabled"); gkeOptions != nil {
			t.Logf("🗑️ Cleaning up GKE without disk enabled...")
			terraform.Destroy(t, gkeOptions)
			t.Logf("✅ GKE disk-disabled cleanup completed")
		} else {
			t.Logf("♻️ No GKE disk-disabled to cleanup (was not created in this test)")
		}
	})

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

// TestFullDeployment tests network creation followed by database and GKE
func (suite *StagedDeploymentSuite) TestFullDeployment() {
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
		dirs, err := os.ReadDir(stateBaseDir)
		if err != nil || len(dirs) == 0 {
			t.Fatal("❌ Cannot skip network creation: No existing network state found. Run without SKIP_setup_network first.")
		}

		// Use the most recent state directory
		var latestDir string
		for _, dir := range dirs {
			if dir.IsDir() {
				latestDir = dir.Name()
				break
			}
		}

		if latestDir == "" {
			t.Fatal("❌ Cannot skip network creation: No valid network state found.")
		}

		suite.workingDir = fmt.Sprintf("%s/%s", stateBaseDir, latestDir)
		networkName := test_structure.LoadString(t, suite.workingDir, "network_name")
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

	// Stage 3: GKE Setup (parallel for disk-enabled and disk-disabled)
	// GKE Disk-Enabled variant
	test_structure.RunTestStage(t, "setup_gke_disk_enabled", func() {
		// Ensure workingDir is set
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot create GKE: Working directory not set. Run network setup stage first.")
		}

		// Load saved network data
		networkName := test_structure.LoadString(t, suite.workingDir, "network_name")
		subnetName := test_structure.LoadString(t, suite.workingDir, "subnet_name")
		projectID := test_structure.LoadString(t, suite.workingDir, "project_id")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

		// Validate required network data exists
		if networkName == "" || subnetName == "" || projectID == "" || resourceId == "" {
			t.Fatal("❌ Cannot create GKE: Missing network data. Run network setup stage first.")
		}

		t.Logf("🔗 Using infrastructure family: %s for GKE disk-enabled", resourceId)

		gkeOptions := &terraform.Options{
			TerraformDir: "../../gcp/examples/test-gke-disk-enabled",
			Vars: map[string]any{
				"project_id":   projectID,
				"region":       TestRegion,
				"prefix":       resourceId,
				"network_name": networkName,
				"subnet_name":  subnetName,
			},
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/gke-disk-enabled", gkeOptions)

		// Apply
		terraform.InitAndApply(t, gkeOptions)

		// Validate
		clusterName := terraform.Output(t, gkeOptions, "cluster_name")
		suite.NotEmpty(clusterName, "GKE cluster name should not be empty")

		t.Logf("✅ GKE cluster with disk enabled created: %s", clusterName)
	})

	// GKE Disk-Disabled variant
	test_structure.RunTestStage(t, "setup_gke_disk_disabled", func() {
		// Ensure workingDir is set
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot create GKE: Working directory not set. Run network setup stage first.")
		}

		// Load saved network data
		networkName := test_structure.LoadString(t, suite.workingDir, "network_name")
		subnetName := test_structure.LoadString(t, suite.workingDir, "subnet_name")
		projectID := test_structure.LoadString(t, suite.workingDir, "project_id")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

		// Validate required network data exists
		if networkName == "" || subnetName == "" || projectID == "" || resourceId == "" {
			t.Fatal("❌ Cannot create GKE: Missing network data. Run network setup stage first.")
		}

		t.Logf("🔗 Using infrastructure family: %s for GKE disk-disabled", resourceId)

		gkeOptions := &terraform.Options{
			TerraformDir: "../../gcp/examples/test-gke-disk-disabled",
			Vars: map[string]any{
				"project_id":   projectID,
				"region":       TestRegion,
				"prefix":       resourceId,
				"network_name": networkName,
				"subnet_name":  subnetName,
			},
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/gke-disk-disabled", gkeOptions)

		// Apply
		terraform.InitAndApply(t, gkeOptions)

		// Validate
		clusterName := terraform.Output(t, gkeOptions, "cluster_name")
		suite.NotEmpty(clusterName, "GKE cluster name should not be empty")

		t.Logf("✅ GKE cluster without disk enabled created: %s", clusterName)
	})
}

// TestStagedDeploymentSuite runs the test suite
func TestStagedDeploymentSuite(t *testing.T) {
	suite.Run(t, new(StagedDeploymentSuite))
}
