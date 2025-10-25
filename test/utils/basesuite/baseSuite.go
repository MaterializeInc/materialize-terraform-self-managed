package basesuite

import (
	"os"
	"path/filepath"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/config"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/dir"
	"github.com/joho/godotenv"
	"github.com/stretchr/testify/suite"
)

// BaseTestSuite provides common functionality for all cloud provider test suites
type BaseTestSuite struct {
	suite.Suite
	OriginalEnv map[string]string // Store original environment to restore later
	SuiteName   string            // Name of the test suite for logging
}

// SetupBaseSuite initializes common test suite functionality
func (suite *BaseTestSuite) SetupBaseSuite(suiteName string, cloud string, configurations []config.Configuration) {
	suite.SuiteName = suiteName
	suite.T().Logf("🔧 Setting up %s Test Suite", suiteName)

	// Store original environment variables that we might modify
	suite.OriginalEnv = make(map[string]string)

	for _, config := range configurations {
		if value, exists := os.LookupEnv(config.Key); exists {
			suite.OriginalEnv[config.Key] = value
		}
	}

	suite.loadEnvironmentFiles(cloud)

	// Log current configuration
	suite.logEnvironmentConfiguration(configurations)

	suite.T().Logf("✅ Test Suite setup completed")
}

// TearDownBaseSuite cleans up common test suite functionality
func (suite *BaseTestSuite) TearDownBaseSuite() {
	t := suite.T()
	t.Logf("🧹 Tearing down %s Test Suite...", suite.SuiteName)

	// Restore original environment variables
	for envVar, originalValue := range suite.OriginalEnv {
		if originalValue != "" {
			os.Setenv(envVar, originalValue)
		} else {
			os.Unsetenv(envVar)
		}
	}

	t.Logf("✅ Test Suite teardown completed")
}

func (suite *BaseTestSuite) loadEnvironmentFiles(cloudDir string) {
	// Skip loading .env files in GitHub Actions - use repository variables instead
	if os.Getenv("GITHUB_ACTIONS") == "true" {
		suite.T().Logf("🤖 Running in GitHub Actions - skipping .env file loading")
		suite.T().Logf("📋 Configuration will be loaded from repository variables and secrets")
		return
	}

	// First load envs from local.env,
	// if local env file exists the exit without loading other env files
	envFiles := []string{"local.env", ".env"}

	projectRoot := dir.GetProjectRootDir()
	if projectRoot == "" {
		suite.T().Fatalf("⚠️  Error: PROJECT_ROOT not set")
	}
	cloudDirFullPath := filepath.Join(projectRoot, utils.MainTestDir, cloudDir)
	for _, envFile := range envFiles {
		fullPath := filepath.Join(cloudDirFullPath, envFile)
		if _, err := os.Stat(fullPath); err == nil {
			if err := godotenv.Load(fullPath); err != nil {
				suite.T().Fatalf("📁 Failed to load environment from: %s, %v", envFile, err)
			}
			suite.T().Logf("✅ Loaded environment from: %s", envFile)
			return
		}
	}
	suite.T().Fatalf("❌ Neither local.env nor .env found in %s", cloudDirFullPath)
}

// logEnvironmentConfiguration logs the current environment configuration
func (suite *BaseTestSuite) logEnvironmentConfiguration(configurations []config.Configuration) {
	t := suite.T()
	t.Logf("📋 Environment Configuration:")

	if projectRoot := dir.GetProjectRootDir(); projectRoot != "" {
		t.Logf("  🏗️  Project Root: %s", projectRoot)
	} else {
		t.Fatal("⚠️  Error: PROJECT_ROOT not set")
	}

	for _, conf := range configurations {
		value := os.Getenv(conf.Key)
		if value == "" {
			switch conf.Type {
			case config.Critical:
				t.Fatalf("⚠️  FATAL: %s not set!", conf.Key)
			default:
				t.Logf("⚠️  WARNING: %s not set!", conf.Key)
			}
		} else {
			t.Logf("  %s: %s", conf.Key, value)
		}
	}
}
