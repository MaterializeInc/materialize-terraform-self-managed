package config

type ConfigType int

const (
	Default  ConfigType = iota
	Critical            // Critical configurations that must be set for the test to run
)

type Configuration struct {
	Key  string
	Type ConfigType
}

func GetCommonConfigurations() []Configuration {
	return []Configuration{
		{
			Key: "TF_LOG",
		},
		{
			Key: "TF_LOG_PATH",
		},
		{
			Key: "ENVIRONMENT",
		},
		{
			Key: "TF_TEST_REMOTE_BACKEND",
		},
		{
			Key: "TF_TEST_S3_BUCKET",
		},
		{
			Key: "TF_TEST_S3_REGION",
		},
		{
			Key: "TF_TEST_S3_PREFIX",
		},
		{
			Key: "TF_TEST_CLEANUP_REMOTE",
		},
	}
}
