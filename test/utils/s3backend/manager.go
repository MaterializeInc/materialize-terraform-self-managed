package s3backend

import (
	"fmt"
	"testing"
)

// Manager handles S3 backend configuration for test runs
type Manager struct {
	config   *Config
	provider string
	runID    string
}

// NewManager creates a new S3 backend manager
func NewManager(t *testing.T, provider, runID string) (*Manager, error) {
	cfg, err := LoadConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to load S3 backend config: %w", err)
	}

	return &Manager{
		config:   cfg,
		provider: provider,
		runID:    runID,
	}, nil
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
