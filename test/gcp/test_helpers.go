package test

import (
	"math/rand"
	"time"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/config"
)

// generateGCPCompliantID generates a random ID that complies with GCP naming requirements
// GCP regex: ^(?:[a-z](?:[-a-z0-9]{0,61}[a-z0-9])?)$
// Must start with lowercase letter, contain only lowercase letters/numbers/hyphens, end with letter/number
func generateGCPCompliantID() string {
	rand.New(rand.NewSource(time.Now().UnixNano()))

	// Start with a random lowercase letter
	const letters = "abcdefghijklmnopqrstuvwxyz"
	const alphanumeric = "abcdefghijklmnopqrstuvwxyz0123456789"

	// Generate 6-character ID: letter + 4 middle chars + letter/number
	result := string(letters[rand.Intn(len(letters))])

	for i := 0; i < 4; i++ {
		result += string(alphanumeric[rand.Intn(len(alphanumeric))])
	}

	// End with letter or number (no hyphen)
	result += string(alphanumeric[rand.Intn(len(alphanumeric))])

	return result
}

func getRequiredGCPConfigurations() []config.Configuration {
	return []config.Configuration{
		{
			Key:  "GOOGLE_PROJECT",
			Type: config.Critical,
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
			Key: "SKIP_setup_gke_disk_disabled",
		},
		{
			Key: "SKIP_cleanup_gke_disk_disabled",
		},
		{
			Key: "SKIP_setup_gke_disk_enabled",
		},
		{
			Key: "SKIP_cleanup_gke_disk_enabled",
		},
		{
			Key: "SKIP_setup_materialize_disk_enabled",
		},
		{
			Key: "SKIP_cleanup_materialize_disk_enabled",
		},
	}
}
