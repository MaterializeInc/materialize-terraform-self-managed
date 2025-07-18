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

	// Cleanup stages (run in reverse order: Materialize, then GKE, then database, then network)
	test_structure.RunTestStage(t, "cleanup_materialize_disk_enabled", func() {
		// Only cleanup if Materialize disk-enabled was created in this test run
		if mzOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/materialize-disk-enabled"); mzOptions != nil {
			t.Logf("🗑️ Cleaning up Materialize with disk enabled...")
			terraform.Destroy(t, mzOptions)
			t.Logf("✅ Materialize disk-enabled cleanup completed")
		} else {
			t.Logf("♻️ No Materialize disk-enabled to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_materialize_disk_disabled", func() {
		// Only cleanup if Materialize disk-disabled was created in this test run
		if mzOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/materialize-disk-disabled"); mzOptions != nil {
			t.Logf("🗑️ Cleaning up Materialize without disk enabled...")
			terraform.Destroy(t, mzOptions)
			t.Logf("✅ Materialize disk-disabled cleanup completed")
		} else {
			t.Logf("♻️ No Materialize disk-disabled to cleanup (was not created in this test)")
		}
	})

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

// TestFullDeployment tests full infrastructure deployment with Materialize
// Stages: Network → Database → GKE (parallel) → Materialize Operator (parallel) → Materialize Instance (parallel)
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
				"database_password": TestPassword,
				"database_name":     TestDBName,
				"user_name":         TestDBUsername,
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
			TerraformDir: "../../gcp/examples/disk-enabled/test-gke-w-nodes",
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
			TerraformDir: "../../gcp/examples/disk-disabled/test-gke-w-nodes",
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

	// Stage 4: Materialize Full Deployment (disk-enabled) - Two-phase deployment
	test_structure.RunTestStage(t, "setup_materialize_disk_enabled", func() {
		// Ensure workingDir is set
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot install Materialize: Working directory not set. Run network setup stage first.")
		}

		// Load saved data
		projectID := test_structure.LoadString(t, suite.workingDir, "project_id")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
		workloadIdentitySA := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/gke-disk-enabled"), "workload_identity_sa_email")
		clusterEndpoint := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/gke-disk-enabled"), "cluster_endpoint")
		clusterCA := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/gke-disk-enabled"), "cluster_ca_certificate")
		databaseHost := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/database"), "private_ip")

		t.Logf("🔗 Using infrastructure family: %s for Materialize (disk-enabled)", resourceId)

		mzOptions := &terraform.Options{
			TerraformDir: "../../gcp/examples/disk-enabled/test-materialize",
			Vars: map[string]any{
				"project_id":                   projectID,
				"region":                       TestRegion,
				"prefix":                       resourceId,
				"cluster_endpoint":             clusterEndpoint,
				"cluster_ca_certificate":       clusterCA,
				"workload_identity_sa_email":   workloadIdentitySA,
				"database_host":                databaseHost,
				"database_username":            TestDBUsername,
				"database_name":                TestDBName,
				"database_password":            TestPassword,
				"external_login_password":      TestPassword,
				"install_materialize_instance": false, // Phase 1: operator only
			},
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/materialize-disk-enabled", mzOptions)

		// Phase 1: Apply operator only
		terraform.InitAndApply(t, mzOptions)

		t.Logf("✅ Phase 1: Materialize operator installed on disk-enabled cluster")

		// Phase 2: Update variables for instance deployment
		mzOptions.Vars["install_materialize_instance"] = true

		// Phase 2: Apply with instance enabled
		terraform.Apply(t, mzOptions)

		// Validate
		instanceResourceId := terraform.Output(t, mzOptions, "instance_resource_id")
		suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")

		t.Logf("✅ Phase 2: Materialize instance created with disk-based storage: %s", instanceResourceId)
	})

	// Stage 5: Materialize Full Deployment (disk-disabled) - Two-phase deployment
	test_structure.RunTestStage(t, "setup_materialize_disk_disabled", func() {
		// Ensure workingDir is set
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot install Materialize: Working directory not set. Run network setup stage first.")
		}

		// Load saved data
		projectID := test_structure.LoadString(t, suite.workingDir, "project_id")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
		workloadIdentitySA := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/gke-disk-disabled"), "workload_identity_sa_email")
		clusterEndpoint := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/gke-disk-disabled"), "cluster_endpoint")
		clusterCA := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/gke-disk-disabled"), "cluster_ca_certificate")
		databaseHost := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/database"), "private_ip")

		t.Logf("🔗 Using infrastructure family: %s for Materialize (disk-disabled)", resourceId)

		mzOptions := &terraform.Options{
			TerraformDir: "../../gcp/examples/disk-disabled/test-materialize",
			Vars: map[string]any{
				"project_id":                   projectID,
				"region":                       TestRegion,
				"prefix":                       resourceId,
				"cluster_endpoint":             clusterEndpoint,
				"cluster_ca_certificate":       clusterCA,
				"workload_identity_sa_email":   workloadIdentitySA,
				"database_host":                databaseHost,
				"database_username":            TestDBUsername,
				"database_name":                TestDBName,
				"database_password":            TestPassword,
				"external_login_password":      TestPassword,
				"install_materialize_instance": false, // Phase 1: operator only
			},
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/materialize-disk-disabled", mzOptions)

		// Phase 1: Apply operator only
		terraform.InitAndApply(t, mzOptions)

		t.Logf("✅ Phase 1: Materialize operator installed on disk-disabled cluster")

		// Phase 2: Update variables for instance deployment
		mzOptions.Vars["install_materialize_instance"] = true

		// Phase 2: Apply with instance enabled
		terraform.Apply(t, mzOptions)

		// Validate
		instanceResourceId := terraform.Output(t, mzOptions, "instance_resource_id")
		suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")

		t.Logf("✅ Phase 2: Materialize instance created without disk-based storage: %s", instanceResourceId)
	})
}

// TestStagedDeploymentSuite runs the test suite
func TestStagedDeploymentSuite(t *testing.T) {
	suite.Run(t, new(StagedDeploymentSuite))
}
