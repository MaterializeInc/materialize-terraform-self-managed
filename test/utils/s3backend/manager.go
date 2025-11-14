package s3backend

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// Manager handles S3 backend configuration for test runs
type Manager struct {
	config   *Config
	provider string
	runID    string
	s3Client *s3.Client
}

// NewManager creates a new S3 backend manager
func newManager(provider, runID string) (*Manager, error) {
	cfg, err := LoadConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to load S3 backend config: %w", err)
	}

	manager := &Manager{
		config:   cfg,
		provider: provider,
		runID:    runID,
		s3Client: nil,
	}

	// Create S3 client only if backend is enabled
	if cfg.Enabled {
		awsCfg, err := config.LoadDefaultConfig(context.TODO(),
			config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
				cfg.AccessKeyID,
				cfg.SecretAccessKey,
				cfg.SessionToken,
			)),
			config.WithRegion(cfg.Region),
		)
		if err != nil {
			return nil, fmt.Errorf("failed to load AWS config for S3 client: %w", err)
		}

		manager.s3Client = s3.NewFromConfig(awsCfg)
	}

	return manager, nil
}

// GetBackendConfig returns Terraform backend configuration for a specific stage
// stageName should be the stage directory name (e.g., "networking", "materialize-disk-enabled")
// This can be directly assigned to terraform.Options.BackendConfig
func (m *Manager) GetBackendConfig(stageName string) map[string]interface{} {
	if !m.config.Enabled {
		return nil
	}

	backendConfig := m.config.BackendConfig(m.provider, stageName, m.runID)
	result := make(map[string]interface{}, len(backendConfig))
	for k, v := range backendConfig {
		result[k] = v
	}
	return result
}

// IsEnabled returns whether S3 backend is enabled
func (m *Manager) IsEnabled() bool {
	return m.config.Enabled
}

// UploadTfvars uploads terraform.tfvars.json file to S3 when remote backend is enabled
// This enables debugging and cleanup scenarios when CI fails
func (m *Manager) UploadTfvars(t *testing.T, stageName, tfvarsPath string) error {
	if !m.config.Enabled || m.s3Client == nil {
		return nil // Skip upload if S3 backend is not enabled or client not available
	}

	// Check if tfvars file exists
	if _, err := os.Stat(tfvarsPath); os.IsNotExist(err) {
		t.Logf("⚠️ Tfvars file does not exist, skipping S3 upload: %s", tfvarsPath)
		return nil
	}

	// Read the tfvars file
	tfvarsContent, err := os.ReadFile(tfvarsPath)
	if err != nil {
		return fmt.Errorf("failed to read tfvars file %s: %w", tfvarsPath, err)
	}

	// Generate S3 key for tfvars file
	s3Key := m.config.GetTfvarsKey(m.provider, stageName, m.runID)

	// Upload tfvars file to S3 using the pre-configured client
	_, err = m.s3Client.PutObject(context.TODO(), &s3.PutObjectInput{
		Bucket: aws.String(m.config.Bucket),
		Key:    aws.String(s3Key),
		Body:   strings.NewReader(string(tfvarsContent)),
		Metadata: map[string]string{
			"provider":  m.provider,
			"stage":     stageName,
			"run-id":    m.runID,
			"file-type": "terraform-tfvars-json",
		},
	})

	if err != nil {
		return fmt.Errorf("failed to upload tfvars to S3: %w", err)
	}

	t.Logf("☁️ Uploaded tfvars to S3: s3://%s/%s", m.config.Bucket, s3Key)
	return nil
}

// CleanupTestRun deletes all S3 objects for this test run (all stages) using batch operations
func (m *Manager) CleanupTestRun(t *testing.T) error {
	if !m.config.Enabled || m.s3Client == nil {
		return nil // Skip cleanup if S3 backend is not enabled
	}

	// List all objects with this run ID prefix
	prefix := fmt.Sprintf("%s/%s/%s/", m.config.Prefix, m.provider, m.runID)

	listInput := &s3.ListObjectsV2Input{
		Bucket: aws.String(m.config.Bucket),
		Prefix: aws.String(prefix),
	}

	result, err := m.s3Client.ListObjectsV2(context.TODO(), listInput)
	if err != nil {
		return fmt.Errorf("failed to list S3 objects for cleanup: %w", err)
	}

	if len(result.Contents) == 0 {
		t.Logf("🔍 No S3 objects found to cleanup for run: %s", m.runID)
		return nil
	}

	// Prepare objects for batch deletion (up to 1000 objects per request)
	var objectsToDelete []types.ObjectIdentifier
	for _, obj := range result.Contents {
		objectsToDelete = append(objectsToDelete, types.ObjectIdentifier{
			Key: obj.Key,
		})
	}

	// Batch delete all objects for this test run
	deleteInput := &s3.DeleteObjectsInput{
		Bucket: aws.String(m.config.Bucket),
		Delete: &types.Delete{
			Objects: objectsToDelete,
			Quiet:   aws.Bool(false), // We want to see what gets deleted
		},
	}

	deleteResult, err := m.s3Client.DeleteObjects(context.TODO(), deleteInput)
	if err != nil {
		return fmt.Errorf("failed to batch delete S3 objects: %w", err)
	}

	// Log successful deletions
	for _, deleted := range deleteResult.Deleted {
		t.Logf("🗑️ Deleted S3 object: s3://%s/%s", m.config.Bucket, *deleted.Key)
	}

	// Log any errors
	for _, deleteError := range deleteResult.Errors {
		t.Logf("⚠️ Failed to delete S3 object %s: %s", *deleteError.Key, *deleteError.Message)
	}

	t.Logf("✅ S3 cleanup completed for test run: %s (%d objects deleted)", m.runID, len(deleteResult.Deleted))
	return nil
}

// InitManager creates and initializes an S3 backend manager for the specified cloud provider
func InitManager(t *testing.T, provider, uniqueID string) (*Manager, error) {
	manager, err := newManager(provider, uniqueID)
	if err != nil {
		return nil, fmt.Errorf("failed to create S3 backend manager: %w", err)
	}

	if manager.IsEnabled() {
		t.Logf("☁️ S3 remote backend enabled for test: %s (ID: %s)", provider, uniqueID)
	}

	return manager, nil
}
