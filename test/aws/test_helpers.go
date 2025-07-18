package test

import (
	"fmt"
	"io"
	"math/rand"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/joho/godotenv"
	"github.com/stretchr/testify/suite"
)

// generateAWSCompliantID generates a random ID that complies with AWS naming requirements
// AWS requirements: Start with letter, end with letter, contain only letters/numbers/hyphens, under 32 chars
// Format: t{YYMMDDHHMMSS}-{random4}{letter} for timestamp ordering and uniqueness
func generateAWSCompliantID() string {
	rand.New(rand.NewSource(time.Now().UnixNano()))

	// Generate timestamp in YYMMDDHHMMSS format
	now := time.Now()
	timestamp := now.Format("060102150405")

	// Generate 4-character random middle part
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	const letters = "abcdefghijklmnopqrstuvwxyz"

	middle := make([]byte, 4)
	for i := range middle {
		middle[i] = charset[rand.Intn(len(charset))]
	}

	// Ensure it ends with a letter
	endLetter := letters[rand.Intn(len(letters))]

	// Format: t{timestamp}-{random4}{letter}
	return fmt.Sprintf("t%s-%s%c", timestamp, string(middle), endLetter)
}

// copyDir recursively copies a directory from src to dst
func copyDir(src, dst string) error {
	// Get source directory info
	srcInfo, err := os.Stat(src)
	if err != nil {
		return fmt.Errorf("failed to stat source directory %s: %w", src, err)
	}

	// Create destination directory
	if err := os.MkdirAll(dst, srcInfo.Mode()); err != nil {
		return fmt.Errorf("failed to create destination directory %s: %w", dst, err)
	}

	// Read source directory contents
	entries, err := os.ReadDir(src)
	if err != nil {
		return fmt.Errorf("failed to read source directory %s: %w", src, err)
	}

	// Copy each entry
	for _, entry := range entries {
		srcPath := filepath.Join(src, entry.Name())
		dstPath := filepath.Join(dst, entry.Name())

		if entry.IsDir() {
			// Recursively copy subdirectory
			if err := copyDir(srcPath, dstPath); err != nil {
				return err
			}
		} else {
			// Copy file
			if err := copyFile(srcPath, dstPath); err != nil {
				return err
			}
		}
	}

	return nil
}

// copyFile copies a single file from src to dst
func copyFile(src, dst string) error {
	// Open source file
	srcFile, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("failed to open source file %s: %w", src, err)
	}
	defer srcFile.Close()

	// Get source file info
	srcInfo, err := srcFile.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat source file %s: %w", src, err)
	}

	// Create destination file
	dstFile, err := os.OpenFile(dst, os.O_RDWR|os.O_CREATE|os.O_TRUNC, srcInfo.Mode())
	if err != nil {
		return fmt.Errorf("failed to create destination file %s: %w", dst, err)
	}
	defer dstFile.Close()

	// Copy file contents
	if _, err := io.Copy(dstFile, srcFile); err != nil {
		return fmt.Errorf("failed to copy file contents from %s to %s: %w", src, dst, err)
	}

	return nil
}

// getProjectRoot returns the root directory of the project
// from the PROJECT_ROOT environment variable
func getProjectRoot() string {
	if projectRoot := os.Getenv("PROJECT_ROOT"); projectRoot != "" {
		return projectRoot
	}

	// Fallback to current directory if PROJECT_ROOT not set
	return "."
}

// setupTestExample copies a specific example to the test workspace
func setupTestExample(t *testing.T, uniqueID, exampleName string) string {
	projectRoot := getProjectRoot()
	srcDir := filepath.Join(projectRoot, "aws", "examples", exampleName)
	dstDir := filepath.Join(projectRoot, "aws", fmt.Sprintf("%s-examples", uniqueID), exampleName)

	t.Logf("📁 Setting up test example: %s -> %s", exampleName, dstDir)

	err := copyDir(srcDir, dstDir)
	if err != nil {
		t.Fatalf("Failed to setup test example %s: %v", exampleName, err)
	}

	t.Logf("✅ Test example ready: %s", dstDir)
	return dstDir
}

// cleanupTestWorkspace removes the test workspace directory
func cleanupTestWorkspace(t *testing.T, uniqueID string) {
	projectRoot := getProjectRoot()
	workspaceDir := filepath.Join(projectRoot, "aws", fmt.Sprintf("%s-examples", uniqueID))

	t.Logf("🧹 Cleaning up test workspace: %s", workspaceDir)

	err := os.RemoveAll(workspaceDir)
	if err != nil {
		t.Logf("⚠️ Failed to cleanup test workspace: %v", err)
	} else {
		t.Logf("✅ Test workspace cleaned up")
	}
}

// BaseTestSuite provides common functionality for all AWS test suites
type BaseTestSuite struct {
	suite.Suite
	originalEnv         map[string]string             // Store original environment to restore later
	terraformOptionsMap map[string]*terraform.Options // Store terraform options for cleanup
	suiteName           string                        // Name of the test suite for logging
	uniqueID            string                        // Unique ID for this test run
}

// SetupBaseSuite initializes common test suite functionality
func (suite *BaseTestSuite) SetupBaseSuite(suiteName string) {
	suite.suiteName = suiteName
	suite.uniqueID = generateAWSCompliantID()
	suite.T().Logf("🔧 Setting up %s Test Suite with ID: %s", suiteName, suite.uniqueID)

	// Initialize the terraform options map
	suite.terraformOptionsMap = make(map[string]*terraform.Options)

	// Store original environment variables that we might modify
	suite.originalEnv = make(map[string]string)
	envVarsToTrack := []string{
		"TF_LOG", "TF_LOG_PATH", "TERRATEST_LOG_PARSER", "TERRATEST_TIMEOUT",
		"AWS_REGION", "AWS_DEFAULT_REGION", "AWS_PROFILE",
		"TEST_REGION", "TEST_MAX_RETRIES", "TEST_RETRY_DELAY",
		"PROJECT_ROOT",
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

	// Clean up test workspace
	if suite.uniqueID != "" {
		cleanupTestWorkspace(t, suite.uniqueID)
	}

	// Restore original environment variables
	for envVar, originalValue := range suite.originalEnv {
		if originalValue != "" {
			os.Setenv(envVar, originalValue)
		} else {
			os.Unsetenv(envVar)
		}
	}

	// Clean up debug log files if they exist
	suite.cleanupDebugFiles()

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

// StoreTerraformOptions stores terraform options for a test for later cleanup
func (suite *BaseTestSuite) StoreTerraformOptions(testName string, options *terraform.Options) {
	suite.terraformOptionsMap[testName] = options
}

// SetupTestExample sets up a specific test example and returns its path
func (suite *BaseTestSuite) SetupTestExample(exampleName string) string {
	return setupTestExample(suite.T(), suite.uniqueID, exampleName)
}

// GetUniqueID returns the unique ID for this test run
func (suite *BaseTestSuite) GetUniqueID() string {
	return suite.uniqueID
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

	if projectRoot := getProjectRoot(); projectRoot != "." {
		t.Logf("  🏗️  Project Root: %s", projectRoot)
	} else {
		t.Logf("  ⚠️  WARNING: PROJECT_ROOT not set, using current directory")
	}

	if region := os.Getenv("AWS_REGION"); region != "" {
		t.Logf("  🌍 AWS Region: %s", region)
	} else if region := os.Getenv("AWS_DEFAULT_REGION"); region != "" {
		t.Logf("  🌍 AWS Default Region: %s", region)
	} else {
		t.Logf("  ⚠️  WARNING: AWS_REGION not set, using default: %s", TestRegion)
	}

	if profile := os.Getenv("AWS_PROFILE"); profile != "" {
		t.Logf("  👤 AWS Profile: %s", profile)
	}

	if tfLog := os.Getenv("TF_LOG"); tfLog != "" {
		t.Logf("  📝 Terraform Log Level: %s", tfLog)
	}

	if tfLogPath := os.Getenv("TF_LOG_PATH"); tfLogPath != "" {
		t.Logf("  📄 Terraform Log File: %s", tfLogPath)
	}

	if profile := os.Getenv("AWS_PROFILE"); profile != "" {
		t.Logf("  🔑 Using AWS profile credentials")
	} else {
		t.Logf("  🔑 Using default AWS credentials")
	}
}

// cleanupDebugFiles cleans up debug log files
func (suite *BaseTestSuite) cleanupDebugFiles() {
	t := suite.T()
	debugFiles := []string{"terraform-debug.log", "test-*.log"}
	for _, pattern := range debugFiles {
		if pattern == "terraform-debug.log" {
			if _, err := os.Stat(pattern); err == nil {
				t.Logf("📄 Debug log available at: %s", pattern)
			}
		}
	}
}
