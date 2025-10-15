package s3backend

import (
	"fmt"
	"os"
	"strconv"
)

// Config holds the S3 backend configuration from environment variables
type Config struct {
	// Enable/disable S3 backend
	Enabled bool
	// S3 bucket name
	Bucket string
	// AWS region for S3
	Region string
	// Optional prefix for all S3 keys
	Prefix string
	// Cleanup remote files on test cleanup
	CleanupRemote bool
}

// LoadConfig loads S3 backend configuration from environment variables
func LoadConfig() (*Config, error) {
	enabled := os.Getenv("TF_TEST_REMOTE_BACKEND")
	if enabled == "" {
		enabled = "false" // default to false
	}

	isEnabled, err := strconv.ParseBool(enabled)
	if err != nil {
		return nil, fmt.Errorf("invalid TF_TEST_REMOTE_BACKEND value: %s", enabled)
	}

	if !isEnabled {
		return &Config{Enabled: false}, nil
	}

	// If enabled, validate required fields
	bucket := os.Getenv("TF_TEST_S3_BUCKET")
	if bucket == "" {
		return nil, fmt.Errorf("TF_TEST_S3_BUCKET is required when TF_TEST_REMOTE_BACKEND is enabled")
	}

	region := os.Getenv("TF_TEST_S3_REGION")
	if region == "" {
		region = "us-east-1" // default region
	}

	prefix := os.Getenv("TF_TEST_S3_PREFIX")
	if prefix == "" {
		prefix = "test-runs" // default prefix
	}

	cleanup := os.Getenv("TF_TEST_CLEANUP_REMOTE")
	if cleanup == "" {
		cleanup = "true" // default to cleanup
	}

	cleanupRemote, err := strconv.ParseBool(cleanup)
	if err != nil {
		return nil, fmt.Errorf("invalid TF_TEST_CLEANUP_REMOTE value: %s", cleanup)
	}

	return &Config{
		Enabled:       true,
		Bucket:        bucket,
		Region:        region,
		Prefix:        prefix,
		CleanupRemote: cleanupRemote,
	}, nil
}

// IsEnabled returns whether S3 backend is enabled
func (c *Config) IsEnabled() bool {
	return c.Enabled
}

// GetStateKey returns the S3 key for tfstate file
func (c *Config) GetStateKey(provider, testName, runID string) string {
	return fmt.Sprintf("%s/%s/%s/%s/terraform.tfstate", c.Prefix, provider, runID, testName)
}
