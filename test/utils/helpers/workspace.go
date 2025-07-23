package helpers

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/dir"
)

// SetupTestWorkspace copies a specific example to the test workspace
func SetupTestWorkspace(t *testing.T, cloudDir, uniqueID, exampleName string) string {
	projectRoot := dir.GetProjectRootDir()
	if projectRoot == "" {
		t.Fatalf("Failed to get Project Root Dir")
	}
	cloudDirFullPath := filepath.Join(projectRoot, cloudDir)
	srcDir := filepath.Join(cloudDirFullPath, utils.ExamplesDir, exampleName)
	dstDir := filepath.Join(cloudDirFullPath, fmt.Sprintf("%s-%s", uniqueID, utils.ExamplesDir), exampleName)

	if _, err := os.Stat(dstDir); !os.IsNotExist(err) {
		t.Logf("Using existing test example: %s", dstDir)
		return dstDir
	}

	t.Logf("📁 Setting up test example: %s -> %s", exampleName, dstDir)

	err := dir.CopyDir(srcDir, dstDir)
	if err != nil {
		t.Fatalf("Failed to setup test example %s: %v", exampleName, err)
	}

	t.Logf("✅ Test example ready: %s", dstDir)
	return dstDir
}

// CleanupTestWorkspace removes the test workspace directory
func CleanupTestWorkspace(t *testing.T, cloudDir, uniqueID, exampleName string) {
	projectRoot := dir.GetProjectRootDir()
	if projectRoot == "" {
		t.Log("Failed to get Project Root Dir, cleanup might not be successful")
	}
	cloudDirFullPath := filepath.Join(projectRoot, cloudDir)
	workspaceDir := filepath.Join(cloudDirFullPath, fmt.Sprintf("%s-%s", uniqueID, utils.ExamplesDir), exampleName)

	t.Logf("🧹 Cleaning up test workspace: %s", workspaceDir)

	err := os.RemoveAll(workspaceDir)
	if err != nil {
		t.Logf("⚠️ Failed to cleanup test workspace: %v", err)
	} else {
		t.Logf("✅ Test workspace cleaned up")
	}
}
