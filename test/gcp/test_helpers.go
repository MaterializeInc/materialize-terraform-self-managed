package test

import (
	"fmt"
	"math/rand"
	"os"
	"strings"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/joho/godotenv"
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

// GetLatestModifiedSubDir returns the most recently modified subdirectory within the root directory
func GetLatestModifiedSubDir(root string) (string, error) {
	// Read only the immediate directory entries
	entries, err := os.ReadDir(root)
	if err != nil {
		return "", fmt.Errorf("failed to read directory %s: %w", root, err)
	}

	var latestDir string
	var latestModTime time.Time

	for _, entry := range entries {
		// Skip non-directories and hidden directories
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}

		// Get full path - use string concatenation to preserve relative paths
		fullPath := root + "/" + entry.Name()
		info, err := entry.Info()
		if err != nil {
			// Skip entries we can't stat
			continue
		}

		// Track the most recent directory
		if latestDir == "" || info.ModTime().After(latestModTime) {
			latestModTime = info.ModTime()
			latestDir = fullPath
		}
	}

	if latestDir == "" {
		return "", fmt.Errorf("no subdirectories found in %s", root)
	}

	return latestDir, nil
}

// BaseTestSuite provides common functionality for all GCP test suites
type BaseTestSuite struct {
	suite.Suite
	originalEnv         map[string]string             // Store original environment to restore later
	terraformOptionsMap map[string]*terraform.Options // Store terraform options for cleanup
	suiteName           string                        // Name of the test suite for logging
}

// SetupBaseSuite initializes common test suite functionality
func (suite *BaseTestSuite) SetupBaseSuite(suiteName string) {
	suite.suiteName = suiteName
	suite.T().Logf("🔧 Setting up %s Test Suite...", suiteName)

	// Initialize the terraform options map
	suite.terraformOptionsMap = make(map[string]*terraform.Options)

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
	suite.loadEnvironmentFiles()

	// Log current configuration
	suite.logEnvironmentConfiguration()

	suite.T().Logf("✅ Test Suite setup completed")
}

// TearDownBaseSuite cleans up common test suite functionality
func (suite *BaseTestSuite) TearDownBaseSuite() {
	t := suite.T()
	t.Logf("🧹 Tearing down %s Test Suite...", suite.suiteName)

	// Restore original environment variables
	for envVar, originalValue := range suite.originalEnv {
		if originalValue != "" {
			os.Setenv(envVar, originalValue)
		} else {
			os.Unsetenv(envVar)
		}
	}

	t.Logf("✅ Test Suite teardown completed")
}

// BaseAfterTest provides common cleanup functionality for individual tests
func (suite *BaseTestSuite) BaseAfterTest(testName string) {
	t := suite.T()
	t.Logf("🧹 Starting cleanup for test: %s", testName)

	// Get terraform options for this test
	if terraformOptions, exists := suite.terraformOptionsMap[testName]; exists {
		t.Logf("🧹 Destroying Terraform resources for %s...", testName)

		// Use Terratest's built-in destroy with retry
		terraform.Destroy(t, terraformOptions)

		t.Logf("✅ Cleanup completed for %s", testName)

		// Remove from map to free memory
		delete(suite.terraformOptionsMap, testName)
	} else {
		t.Logf("⚠️ No terraform options found for test: %s", testName)
	}
}

// loadEnvironmentFiles tries to load environment files for debugging configuration
func (suite *BaseTestSuite) loadEnvironmentFiles() {
	envFiles := []string{".env", "debug.env", ".env.debug", ".env.local"}

	for _, envFile := range envFiles {
		if err := godotenv.Load(envFile); err == nil {
			suite.T().Logf("📁 Loaded environment from: %s", envFile)
			break
		}
	}
}

// logEnvironmentConfiguration logs the current environment configuration
func (suite *BaseTestSuite) logEnvironmentConfiguration() {
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
}
