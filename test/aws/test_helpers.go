package test

import (
	"fmt"
	"io"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
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

// setupTestExample copies a specific example to the test workspace
func setupTestExample(t *testing.T, cloudDir, uniqueID, exampleName string) string {
	projectRoot := getProjectRootDir()
	if projectRoot == "" {
		t.Fatalf("Failed to get Project Root Dir")
	}
	cloudDirFullPath := filepath.Join(projectRoot, cloudDir)
	srcDir := filepath.Join(cloudDirFullPath, ExamplesDir, exampleName)
	dstDir := filepath.Join(cloudDirFullPath, fmt.Sprintf("%s-%s", uniqueID, ExamplesDir), exampleName)

	if _, err := os.Stat(dstDir); !os.IsNotExist(err) {
		t.Logf("Using existing test example: %s", dstDir)
		return dstDir
	}

	t.Logf("📁 Setting up test example: %s -> %s", exampleName, dstDir)

	err := copyDir(srcDir, dstDir)
	if err != nil {
		t.Fatalf("Failed to setup test example %s: %v", exampleName, err)
	}

	t.Logf("✅ Test example ready: %s", dstDir)
	return dstDir
}

// cleanupTestWorkspace removes the test workspace directory
func cleanupTestWorkspace(t *testing.T, cloudDir, uniqueID, exampleName string) {
	projectRoot := getProjectRootDir()
	if projectRoot == "" {
		t.Log("Failed to get Project Root Dir, cleanup might not be successful")
	}
	cloudDirFullPath := filepath.Join(projectRoot, cloudDir)
	workspaceDir := filepath.Join(cloudDirFullPath, fmt.Sprintf("%s-%s", uniqueID, ExamplesDir), exampleName)

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
}

// SetupBaseSuite initializes common test suite functionality
func (suite *BaseTestSuite) SetupBaseSuite(suiteName string) {
	suite.suiteName = suiteName
	suite.T().Logf("🔧 Setting up %s Test Suite", suiteName)

	// Initialize the terraform options map
	suite.terraformOptionsMap = make(map[string]*terraform.Options)

	// Store original environment variables that we might modify
	suite.originalEnv = make(map[string]string)
	envVarsToTrack := []string{
		"TF_LOG", "TF_LOG_PATH", "TERRATEST_LOG_PARSER", "TERRATEST_TIMEOUT",
		"AWS_REGION", "AWS_DEFAULT_REGION", "AWS_PROFILE",
		"TEST_REGION", "TEST_MAX_RETRIES", "TEST_RETRY_DELAY",
		"PROJECT_ROOT", "USE_EXISING_NETWORK",
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

	if projectRoot := getProjectRootDir(); projectRoot != "" {
		t.Logf("  🏗️  Project Root: %s", projectRoot)
	} else {
		t.Fatal("⚠️  Error: PROJECT_ROOT not set")
	}

	if profile := os.Getenv("AWS_PROFILE"); profile != "" {
		t.Logf("  👤 AWS Profile: %s", profile)
	} else {
		t.Fatal(" 👤 Error: AWS Profile not set")
	}

	if region := os.Getenv("AWS_REGION"); region != "" {
		t.Logf("  🌍 AWS Region: %s", region)
	} else {
		t.Fatal(" 🌍 Error: AWS Region not set")
	}

	if tfLog := os.Getenv("TF_LOG"); tfLog != "" {
		t.Logf("  📝 Terraform Log Level: %s", tfLog)
	}

	if tfLogPath := os.Getenv("TF_LOG_PATH"); tfLogPath != "" {
		t.Logf("  📄 Terraform Log File: %s", tfLogPath)
	}
}

func getProjectRootDir() string {
	var projectRoot string
	if projectRoot = os.Getenv("PROJECT_ROOT"); projectRoot != "" {
		return projectRoot
	}

	outPut, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		fmt.Printf("⚠️  WARNING: PROJECT_ROOT not set and failed to determine using git command: %v",
			err)
		return ""
	}
	projectRoot = strings.TrimSuffix(string(outPut), "\n")

	os.Setenv("PROJECT_ROOT", projectRoot)
	return string(projectRoot)
}

func GetLastRunTestStageDir() (string, error) {
	// Find and load existing network state
	stageOutputBaseDir := TestRunsDir

	// Check if state base directory exists
	if _, err := os.Stat(stageOutputBaseDir); os.IsNotExist(err) {
		return "", err
	}

	// Get the most recent state directory
	latestDirPath, err := GetLatestModifiedSubDir(stageOutputBaseDir)
	if err != nil {
		return "", err
	}

	return latestDirPath, nil
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
