package test

import (
	"fmt"
	"math/rand"
	"os"
	"time"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/config"
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

func getRequiredAWSConfigurations() []config.Configuration {
	return []config.Configuration{
		{
			Key:  "AWS_REGION",
			Type: config.Critical,
		},
		{
			Key: "AWS_PROFILE",
		},
		{
			Key: "MATERIALIZE_LICENSE_KEY",
		},
		{
			Key: "USE_EXISING_NETWORK",
		},
		{
			Key: "SKIP_setup_network",
		},
		{
			Key: "SKIP_cleanup_network",
		},
		{
			Key: "SKIP_testDiskEnabled",
		},
		{
			Key: "SKIP_cleanup_testDiskEnabled",
		},
		{
			Key: "SKIP_testDiskDisabled",
		},
		{
			Key: "SKIP_cleanup_testDiskDisabled",
		},
	}
}

// getAWSProfileForTerraform returns the AWS profile for terraform configuration
// Returns empty string when running in GitHub Actions (OIDC environment)
func getAWSProfileForTerraform() string {
	profile := os.Getenv("AWS_PROFILE")

	// Check if we're running in GitHub Actions
	if os.Getenv("GITHUB_ACTIONS") == "true" {
		// In GitHub Actions, credentials are provided via OIDC, no profile needed
		return ""
	}

	return profile
}
