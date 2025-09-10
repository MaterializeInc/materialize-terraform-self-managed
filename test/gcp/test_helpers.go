package test

import (
	"fmt"
	"math/rand"
	"time"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/config"
)

// generateGCPCompliantID generates a random ID that complies with GCP naming requirements
// Must start with lowercase letter, contain only lowercase letters/numbers/hyphens, end with letter/number
// Format: t{YYMMDDHHMMSS}-{letter}{random4}{letter} for timestamp ordering and uniqueness
func generateGCPCompliantID() string {
	rand.New(rand.NewSource(time.Now().UnixNano()))

	// Generate timestamp in YYMMDDHHMMSS format
	now := time.Now()
	timestamp := now.Format("060102150405")

	// Generate random parts
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	const letters = "abcdefghijklmnopqrstuvwxyz"

	// Start with a letter
	startLetter := letters[rand.Intn(len(letters))]

	// Generate 4-character random middle part
	middle := make([]byte, 4)
	for i := range middle {
		middle[i] = charset[rand.Intn(len(charset))]
	}

	// End with a letter (GCP requires ending with letter or number, we use letter for consistency)
	endLetter := letters[rand.Intn(len(letters))]

	// Format: t{timestamp}-{letter}{random4}{letter}
	return fmt.Sprintf("t%s-%c%s%c", timestamp, startLetter, string(middle), endLetter)
}

func getRequiredGCPConfigurations() []config.Configuration {
	return []config.Configuration{
		{
			Key:  "GOOGLE_PROJECT",
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
			Key: "SKIP_setup_database",
		},
		{
			Key: "SKIP_cleanup_database",
		},
		{
			Key: "SKIP_setup_gke_disk_enabled",
		},
		{
			Key: "SKIP_cleanup_gke_disk_enabled",
		},
		{
			Key: "SKIP_setup_gke_disk_disabled",
		},
		{
			Key: "SKIP_cleanup_gke_disk_disabled",
		},
		{
			Key: "SKIP_setup_materialize_disk_enabled",
		},
		{
			Key: "SKIP_cleanup_materialize_disk_enabled",
		},
		{
			Key: "SKIP_setup_materialize_disk_disabled",
		},
		{
			Key: "SKIP_cleanup_materialize_disk_disabled",
		},
	}
}
