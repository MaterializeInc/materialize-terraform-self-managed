package s3backend

// BackendConfig generates Terraform backend configuration for S3
// Returns a map that can be used with terraform.Options.BackendConfig
func (c *Config) BackendConfig(provider, testName, runID string) map[string]string {
	if !c.Enabled {
		return nil
	}

	stateKey := c.GetStateKey(provider, testName, runID)

	backendConfig := map[string]string{
		"bucket":                      c.Bucket,
		"key":                         stateKey,
		"region":                      c.Region,
		"access_key":                  c.AccessKeyID,
		"secret_key":                  c.SecretAccessKey,
		"skip_credentials_validation": "false",
		"skip_metadata_api_check":     "false",
	}

	// Add session token if provided (for temporary credentials)
	if c.SessionToken != "" {
		backendConfig["token"] = c.SessionToken
	}

	return backendConfig
}
