package helpers

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// CreateTfvarsFile creates a terraform.tfvars.json file using JSON format
// This is a generic function that can be used across different test suites (AWS, Azure, GCP)
func CreateTfvarsFile(t *testing.T, tfvarsPath string, variables map[string]interface{}) {
	// Convert the variables map to JSON
	jsonBytes, err := json.MarshalIndent(variables, "", "  ")
	if err != nil {
		t.Fatalf("Failed to marshal variables to JSON: %v", err)
	}

	err = os.WriteFile(tfvarsPath, jsonBytes, 0644)
	if err != nil {
		t.Fatalf("Failed to create terraform.tfvars.json file: %v", err)
	}

	t.Logf("📝 Created terraform.tfvars.json file: %s", tfvarsPath)
}

func SafeLoadTerraformOptions(t *testing.T, testDataDir string) *terraform.Options {
	terraformOptionsPath := test_structure.FormatTestDataPath(testDataDir, "TerraformOptions.json")

	if !test_structure.IsTestDataPresent(t, terraformOptionsPath) {
		return nil
	}

	return test_structure.LoadTerraformOptions(t, testDataDir)
}
