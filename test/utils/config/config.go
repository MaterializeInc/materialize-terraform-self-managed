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
	}
}
