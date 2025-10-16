package test

import (
	"fmt"
	"testing"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/s3backend"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// initS3BackendManager creates and initializes an S3 backend manager
func initS3BackendManager(t *testing.T, uniqueID string) (*s3backend.Manager, error) {
	manager, err := s3backend.NewManager(t, utils.AWS, uniqueID)
	if err != nil {
		return nil, fmt.Errorf("failed to create S3 backend manager: %w", err)
	}

	if manager.IsEnabled() {
		t.Logf("☁️ S3 remote backend enabled for test: %s (ID: %s)", utils.AWS, uniqueID)
	}

	return manager, nil
}

// applyBackendConfigToTerraformOptions adds S3 backend configuration to terraform options
// stageName should be the stage directory name (e.g., "networking", "materialize-disk-enabled")
// Terraform will automatically use this configuration during init
func applyBackendConfigToTerraformOptions(options *terraform.Options, manager *s3backend.Manager, stageName string) {
	if !manager.IsEnabled() {
		return
	}

	// Set backend configuration - terratest will pass these to terraform init
	// Terraform's S3 backend will handle all state management automatically
	options.BackendConfig = manager.GetBackendConfig(stageName)
}
