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
	// AWS credentials for S3 access
	AccessKeyID     string
	SecretAccessKey string
	SessionToken    string // Optional
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
		return nil, fmt.Errorf("TF_TEST_S3_REGION is required when TF_TEST_REMOTE_BACKEND is enabled")
	}

	prefix := os.Getenv("TF_TEST_S3_PREFIX")
	if prefix == "" {
		prefix = "test-runs" // default prefix
	}

	// Load AWS credentials from environment variables
	// These are required for S3 backend access in CI/CD environments
	accessKeyID := os.Getenv("AWS_ACCESS_KEY_ID")
	secretAccessKey := os.Getenv("AWS_SECRET_ACCESS_KEY")
	sessionToken := os.Getenv("AWS_SESSION_TOKEN") // Optional

	// Validate required credentials
	if accessKeyID == "" {
		return nil, fmt.Errorf("AWS_ACCESS_KEY_ID is required when TF_TEST_REMOTE_BACKEND is enabled")
	}
	if secretAccessKey == "" {
		return nil, fmt.Errorf("AWS_SECRET_ACCESS_KEY is required when TF_TEST_REMOTE_BACKEND is enabled")
	}

	return &Config{
		Enabled:         true,
		Bucket:          bucket,
		Region:          region,
		Prefix:          prefix,
		AccessKeyID:     accessKeyID,
		SecretAccessKey: secretAccessKey,
		SessionToken:    sessionToken,
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
