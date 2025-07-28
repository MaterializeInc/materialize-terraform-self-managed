package test

import (
	"fmt"
	"math/rand"
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
			Key:  "AWS_PROFILE",
			Type: config.Critical,
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
			Key: "SKIP_setup_eks_disk_enabled",
		},
		{
			Key: "SKIP_cleanup_eks_disk_enabled",
		},
		{
			Key: "SKIP_setup_eks_disk_disabled",
		},
		{
			Key: "SKIP_cleanup_eks_disk_disabled",
		},
		{
			Key: "SKIP_setup_database",
		},
		{
			Key: "SKIP_cleanup_database",
		},
	}
}
