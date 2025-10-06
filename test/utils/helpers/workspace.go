package helpers

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/dir"
)

// SetupTestWorkspace copies a specific fixture to the test workspace
func SetupTestWorkspace(t *testing.T, cloudDir, uniqueID, fixtureName, destinationName string) string {
	projectRoot := dir.GetProjectRootDir()
	if projectRoot == "" {
		t.Fatalf("Failed to get Project Root Dir")
	}

	// Source: test/{cloud}/fixtures/{fixtureName}
	testCloudDir := filepath.Join(projectRoot, utils.MainTestDir, cloudDir)
	srcDir := filepath.Join(testCloudDir, utils.FixturesDir, fixtureName)

	// Destination: test/{cloud}/{uniqueID}/{destinationName}
	dstDir := filepath.Join(testCloudDir, uniqueID, destinationName)

	t.Logf("📁 Setting up test fixture: %s -> %s", fixtureName, dstDir)

	err := dir.CopyDir(srcDir, dstDir)
	if err != nil {
		t.Fatalf("Failed to setup test fixture %s: %v", fixtureName, err)
	}

	t.Logf("✅ Test fixture ready: %s", dstDir)
	return dstDir
}

// CleanupTestWorkspace removes the test workspace directory
func CleanupTestWorkspace(t *testing.T, cloudDir, uniqueID, destinationName string) {
	projectRoot := dir.GetProjectRootDir()
	if projectRoot == "" {
		t.Log("Failed to get Project Root Dir, cleanup might not be successful")
	}

	testCloudDir := filepath.Join(projectRoot, utils.MainTestDir, cloudDir)
	workspaceDir := filepath.Join(testCloudDir, uniqueID, destinationName)

	t.Logf("🧹 Cleaning up test workspace: %s", workspaceDir)

	err := os.RemoveAll(workspaceDir)
	if err != nil {
		t.Logf("⚠️ Failed to cleanup test workspace: %v", err)
	} else {
		t.Logf("✅ Test workspace cleaned up")
	}
}

// GetEnvironment returns the environment from env var or default
func GetEnvironment() string {
	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		environment = "terratest" // default value
	}
	return environment
}
