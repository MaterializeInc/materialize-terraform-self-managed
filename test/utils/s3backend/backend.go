package s3backend

// BackendConfig generates Terraform backend configuration for S3
// Returns a map that can be used with terraform.Options.BackendConfig
func (c *Config) BackendConfig(provider, testName, runID string) map[string]string {
	if !c.Enabled {
		return nil
	}

	stateKey := c.GetStateKey(provider, testName, runID)

	return map[string]string{
		"bucket": c.Bucket,
		"key":    stateKey,
		"region": c.Region,
	}
}
