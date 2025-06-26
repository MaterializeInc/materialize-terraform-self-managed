package test

import (
	"fmt"
	"math/rand"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/gcp"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/joho/godotenv"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// generateGCPCompliantID generates a random ID that complies with GCP naming requirements
// GCP regex: ^(?:[a-z](?:[-a-z0-9]{0,61}[a-z0-9])?)$
// Must start with lowercase letter, contain only lowercase letters/numbers/hyphens, end with letter/number
func generateGCPCompliantID() string {
	rand.New(rand.NewSource(time.Now().UnixNano()))

	// Start with a random lowercase letter
	const letters = "abcdefghijklmnopqrstuvwxyz"
	const alphanumeric = "abcdefghijklmnopqrstuvwxyz0123456789"

	// Generate 6-character ID: letter + 4 middle chars + letter/number
	result := string(letters[rand.Intn(len(letters))])

	for i := 0; i < 4; i++ {
		result += string(alphanumeric[rand.Intn(len(alphanumeric))])
	}

	// End with letter or number (no hyphen)
	result += string(alphanumeric[rand.Intn(len(alphanumeric))])

	return result
}

// NetworkingTestSuite defines the test suite for networking module
type NetworkingTestSuite struct {
	suite.Suite
	originalEnv map[string]string // Store original environment to restore later
}

// SetupSuite runs once before all tests in the suite
func (suite *NetworkingTestSuite) SetupSuite() {
	suite.T().Log("🔧 Setting up Networking Test Suite...")

	// Store original environment variables that we might modify
	suite.originalEnv = make(map[string]string)
	envVarsToTrack := []string{
		"TF_LOG", "TF_LOG_PATH", "TERRATEST_LOG_PARSER", "TERRATEST_TIMEOUT",
		"GOOGLE_PROJECT", "GOOGLE_APPLICATION_CREDENTIALS",
		"TEST_REGION", "TEST_MAX_RETRIES", "TEST_RETRY_DELAY",
	}

	for _, envVar := range envVarsToTrack {
		if value, exists := os.LookupEnv(envVar); exists {
			suite.originalEnv[envVar] = value
		}
	}

	// Try to load .env file for debugging configuration
	envFiles := []string{".env", "debug.env", ".env.debug", ".env.local"}

	for _, envFile := range envFiles {
		if err := godotenv.Load(envFile); err == nil {
			suite.T().Logf("📁 Loaded environment from: %s", envFile)
			break
		}
	}

	// Log current configuration
	t := suite.T()
	t.Logf("📋 Environment Configuration:")
	if projectID := os.Getenv("GOOGLE_PROJECT"); projectID != "" {
		t.Logf("  🏗️  GCP Project: %s", projectID)
	} else {
		t.Logf("  ⚠️  WARNING: GOOGLE_PROJECT not set!")
	}

	if tfLog := os.Getenv("TF_LOG"); tfLog != "" {
		t.Logf("  📝 Terraform Log Level: %s", tfLog)
	}

	if tfLogPath := os.Getenv("TF_LOG_PATH"); tfLogPath != "" {
		t.Logf("  📄 Terraform Log File: %s", tfLogPath)
	}

	if credsPath := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"); credsPath != "" {
		t.Logf("  🔑 Using credentials file: %s", credsPath)
	} else {
		t.Logf("  🔑 Using default application credentials")
	}

	suite.T().Logf("✅ Test Suite setup completed")
}

// TearDownSuite runs once after all tests in the suite
func (suite *NetworkingTestSuite) TearDownSuite() {
	t := suite.T()
	t.Log("🧹 Tearing down Networking Test Suite...")

	// Restore original environment variables
	for envVar, originalValue := range suite.originalEnv {
		if originalValue != "" {
			os.Setenv(envVar, originalValue)
		} else {
			os.Unsetenv(envVar)
		}
	}

	// Clean up debug log files if they exist
	debugFiles := []string{"terraform-debug.log", "test-*.log"}
	for _, pattern := range debugFiles {
		if pattern == "terraform-debug.log" {
			if _, err := os.Stat(pattern); err == nil {
				t.Logf("📄 Debug log available at: %s", pattern)
			}
		}
	}

	t.Logf("✅ Test Suite teardown completed")
}

// TestNetworkingModule tests the basic networking module functionality
func (suite *NetworkingTestSuite) TestNetworkingModule() {
	t := suite.T()
	t.Parallel()

	// Create a GCP-compliant random ID for resources
	uniqueId := generateGCPCompliantID()
	t.Logf("🆔 Generated GCP-compliant unique test ID: %s", uniqueId)

	// GCP Project ID - should be set via environment variable GOOGLE_PROJECT
	projectID := gcp.GetGoogleProjectIDFromEnvVar(t)
	t.Logf("🏗️  Testing with GCP Project: %s", projectID)
	t.Logf("🌍 Testing in region: %s", TestRegion)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../../gcp/modules/networking",

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"project_id":    projectID,
			"region":        TestRegion,                           // Use consistent region
			"prefix":        fmt.Sprintf("test-net-%s", uniqueId), // Shorter prefix for GCP limits
			"subnet_cidr":   TestSubnetCIDR,                       // Use non-conflicting CIDR
			"pods_cidr":     TestPodsCIDR,                         // Use non-conflicting CIDR
			"services_cidr": TestServicesCIDR,                     // Use non-conflicting CIDR
		},

		// Disable colors in Terraform commands so its easier to parse stdout/stderr
		NoColor: true,

		// Enhanced settings for debugging
		MaxRetries:         TestMaxRetries,
		TimeBetweenRetries: TestRetryDelay * time.Second,
	})

	t.Logf("🚀 Starting Terraform deployment for networking module...")

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer func() {
		t.Logf("🧹 Starting cleanup - destroying Terraform resources...")
		terraform.Destroy(t, terraformOptions)
		t.Logf("✅ Cleanup completed")
	}()

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	t.Logf("📦 Running terraform init and apply...")
	terraform.InitAndApply(t, terraformOptions)
	t.Logf("✅ Terraform deployment completed successfully")

	// Run `terraform output` to get the value of an output variables
	t.Logf("📊 Retrieving Terraform outputs...")
	networkName := terraform.Output(t, terraformOptions, "network_name")
	networkID := terraform.Output(t, terraformOptions, "network_id")
	subnetName := terraform.Output(t, terraformOptions, "subnet_name")
	subnetID := terraform.Output(t, terraformOptions, "subnet_id")
	routerName := terraform.Output(t, terraformOptions, "router_name")
	natName := terraform.Output(t, terraformOptions, "nat_name")

	// Log all outputs for debugging
	t.Logf("🌐 Network Name: %s", networkName)
	t.Logf("🆔 Network ID: %s", networkID)
	t.Logf("🏠 Subnet Name: %s", subnetName)
	t.Logf("🆔 Subnet ID: %s", subnetID)
	t.Logf("🔀 Router Name: %s", routerName)
	t.Logf("🌍 NAT Name: %s", natName)

	// Verify the network name contains our prefix
	expectedPrefix := fmt.Sprintf("test-net-%s", uniqueId)
	t.Logf("🔍 Verifying prefix: %s", expectedPrefix)

	assert.True(t, strings.Contains(networkName, expectedPrefix),
		"Network name should contain prefix %s, got %s", expectedPrefix, networkName)

	// Verify that outputs are not empty
	assert.NotEmpty(t, networkName, "Network name should not be empty")
	assert.NotEmpty(t, networkID, "Network ID should not be empty")
	assert.NotEmpty(t, subnetName, "Subnet name should not be empty")
	assert.NotEmpty(t, subnetID, "Subnet ID should not be empty")
	assert.NotEmpty(t, routerName, "Router name should not be empty")
	assert.NotEmpty(t, natName, "NAT name should not be empty")

	// Verify the network ID follows the expected GCP format
	assert.True(t, strings.Contains(networkID, "networks/"),
		"Network ID should contain 'networks/', got %s", networkID)
	assert.True(t, strings.Contains(networkID, projectID),
		"Network ID should contain project ID %s, got %s", projectID, networkID)

	// Verify the subnet ID follows the expected GCP format
	assert.True(t, strings.Contains(subnetID, "subnetworks/"),
		"Subnet ID should contain 'subnetworks/', got %s", subnetID)
	assert.True(t, strings.Contains(subnetID, TestRegion),
		"Subnet ID should contain region %s, got %s", TestRegion, subnetID)

	// Verify that the subnet name contains our prefix
	assert.True(t, strings.Contains(subnetName, expectedPrefix),
		"Subnet name should contain prefix %s, got %s", expectedPrefix, subnetName)

	// Verify that the router name contains our prefix
	assert.True(t, strings.Contains(routerName, expectedPrefix),
		"Router name should contain prefix %s, got %s", expectedPrefix, routerName)

	// Verify that the NAT name contains our prefix
	assert.True(t, strings.Contains(natName, expectedPrefix),
		"NAT name should contain prefix %s, got %s", expectedPrefix, natName)

	// Verify private service connection exists (for database connectivity)
	t.Logf("🔗 Checking private VPC connection...")
	privateConnection := terraform.Output(t, terraformOptions, "private_vpc_connection")
	assert.NotEmpty(t, privateConnection, "Private VPC connection should be created")
	t.Logf("✅ Private VPC connection verified: %s", privateConnection)

	t.Logf("🎉 All networking module tests passed successfully!")
}

// TestNetworkingModuleWithCustomCIDR tests the networking module with custom CIDR ranges
func (suite *NetworkingTestSuite) TestNetworkingModuleWithCustomCIDR() {
	t := suite.T()
	t.Parallel()

	// Create a GCP-compliant random ID for resources
	uniqueId := generateGCPCompliantID()
	t.Logf("🆔 Generated GCP-compliant unique test ID: %s", uniqueId)

	// GCP Project ID - should be set via environment variable GOOGLE_PROJECT
	projectID := gcp.GetGoogleProjectIDFromEnvVar(t)
	t.Logf("🏗️  Testing custom CIDR with GCP Project: %s", projectID)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../../gcp/modules/networking",

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"project_id":    projectID,
			"region":        TestRegion,
			"prefix":        fmt.Sprintf("test-cidr-%s", uniqueId), // Shorter prefix for GCP limits
			"subnet_cidr":   TestCustomSubnetCIDR,                  // Use predefined custom CIDR
			"pods_cidr":     TestCustomPodsCIDR,                    // Use predefined custom CIDR
			"services_cidr": TestCustomServicesCIDR,                // Use predefined custom CIDR
		},

		// Disable colors in Terraform commands
		NoColor: true,

		// Set max retry and sleep between retries for resources that support eventually consistent APIs
		MaxRetries:         TestMaxRetries,
		TimeBetweenRetries: TestRetryDelay * time.Second,
	})

	t.Logf("🚀 Starting custom CIDR test deployment...")

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer func() {
		t.Logf("🧹 Starting cleanup for custom CIDR test...")
		terraform.Destroy(t, terraformOptions)
		t.Logf("✅ Custom CIDR test cleanup completed")
	}()

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)
	t.Logf("✅ Custom CIDR deployment completed successfully")

	// Verify that the subnet has been created successfully
	subnetName := terraform.Output(t, terraformOptions, "subnet_name")
	subnetID := terraform.Output(t, terraformOptions, "subnet_id")

	// Log outputs for debugging
	t.Logf("🏠 Custom Subnet Name: %s", subnetName)
	t.Logf("🆔 Custom Subnet ID: %s", subnetID)

	// Basic assertions on subnet outputs
	assert.NotEmpty(t, subnetName, "Subnet name should not be empty")
	assert.NotEmpty(t, subnetID, "Subnet ID should not be empty")

	// Verify the subnet ID follows the expected GCP format
	assert.True(t, strings.Contains(subnetID, "subnetworks/"),
		"Subnet ID should contain 'subnetworks/', got %s", subnetID)
	assert.True(t, strings.Contains(subnetID, TestRegion),
		"Subnet ID should contain region %s, got %s", TestRegion, subnetID)

	// Verify that the subnet name contains our prefix
	expectedPrefix := fmt.Sprintf("test-cidr-%s", uniqueId)
	assert.True(t, strings.Contains(subnetName, expectedPrefix),
		"Subnet name should contain prefix %s, got %s", expectedPrefix, subnetName)

	t.Logf("🎉 Custom CIDR networking test passed successfully!")
}

// TestNetworkingTestSuite runs the networking test suite
func TestNetworkingTestSuite(t *testing.T) {
	suite.Run(t, new(NetworkingTestSuite))
}
