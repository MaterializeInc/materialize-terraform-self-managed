package test

import (
	"fmt"
	"math/rand"
	"time"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/config"
)

// generateAzureCompliantID generates a random ID that complies with Azure naming requirements
// Azure requirements: Start with letter, contain only letters/numbers/hyphens, under 63 chars
// Format: t{YYMMDDHHMMSS}-{letter}{random3}{letter} for timestamp ordering and uniqueness
func generateAzureCompliantID() string {
	rand.New(rand.NewSource(time.Now().UnixNano()))

	// Generate timestamp in YYMMDDHHMMSS format
	now := time.Now()
	timestamp := now.Format("060102150405")

	// Generate random parts
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	const letters = "abcdefghijklmnopqrstuvwxyz"

	// Start with a letter
	startLetter := letters[rand.Intn(len(letters))]

	// Generate  random middle part
	middle := make([]byte, TestRandomIDLength)
	for i := range middle {
		middle[i] = charset[rand.Intn(len(charset))]
	}

	// End with a letter
	endLetter := letters[rand.Intn(len(letters))]

	// Format: t{timestamp}-{letter}{random3}{letter}
	return fmt.Sprintf(TestResourceIDFormat, timestamp, startLetter, string(middle), endLetter)
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
			Key: "MATERIALIZE_LICENSE_KEY",
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
