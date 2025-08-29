package test

import (
	"fmt"
	"math/rand"
	"time"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/config"
)

// generateAzureCompliantID generates a random ID that complies with Azure naming requirements
// Azure requirements: Start with letter, contain only letters/numbers/hyphens, under 63 chars
// Format: t{YYMMDDHHMMSS}-{random4}{letter} for timestamp ordering and uniqueness
func generateAzureCompliantID() string {
	rand.New(rand.NewSource(time.Now().UnixNano()))

	// Generate timestamp in YYMMDDHHMMSS format
	now := time.Now()
	timestamp := now.Format("060102150405")

	// Generate 4-character random middle part
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	const letters = "abcdefghijklmnopqrstuvwxyz"

	middle := make([]byte, TestRandomIDLength)
	for i := range middle {
		middle[i] = charset[rand.Intn(len(charset))]
	}

	// Ensure it ends with a letter
	endLetter := letters[rand.Intn(len(letters))]

	// Format: t{timestamp}-{random4}{letter}
	return fmt.Sprintf(TestResourceIDFormat, timestamp, string(middle), endLetter)
}

func getRequiredAzureConfigurations() []config.Configuration {
	return []config.Configuration{
		{
			Key:  "ARM_SUBSCRIPTION_ID",
			Type: config.Critical,
		},
		{
			Key:  "TEST_REGION",
			Type: config.Critical,
		},
		{
			Key: "USE_EXISTING_NETWORK",
		},
		{
			Key: "SKIP_setup_network",
		},
		{
			Key: "SKIP_cleanup_network",
		},
		{
			Key: "SKIP_setup_aks_disk_enabled",
		},
		{
			Key: "SKIP_cleanup_aks_disk_enabled",
		},
		{
			Key: "SKIP_setup_database_disk_enabled",
		},
		{
			Key: "SKIP_cleanup_database_disk_enabled",
		},
		{
			Key: "SKIP_setup_materialize_disk_enabled",
		},
		{
			Key: "SKIP_cleanup_materialize_disk_enabled",
		},
	}
}
