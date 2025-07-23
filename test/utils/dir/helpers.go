package dir

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

func GetProjectRootDir() string {
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

func GetLastRunTestStageDir(baseDir string) (string, error) {
	// Check if state base directory exists
	if _, err := os.Stat(baseDir); os.IsNotExist(err) {
		return "", err
	}

	// Get the most recent state directory
	latestDirPath, err := GetLatestModifiedSubDir(baseDir)
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
