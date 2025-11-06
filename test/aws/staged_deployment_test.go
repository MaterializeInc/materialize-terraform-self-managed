package test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/basesuite"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/config"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/dir"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/helpers"
	"github.com/MaterializeInc/materialize-terraform-self-managed/test/utils/s3backend"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/suite"
)

// StagedDeploymentTestSuite tests the full AWS infrastructure deployment in stages
type StagedDeploymentTestSuite struct {
	basesuite.BaseTestSuite
	workingDir string
	uniqueId   string
	s3Manager  *s3backend.Manager
}

// SetupSuite initializes the test suite
func (suite *StagedDeploymentTestSuite) SetupSuite() {
	configurations := config.GetCommonConfigurations()
	configurations = append(configurations, getRequiredAWSConfigurations()...)
	suite.SetupBaseSuite("AWS Staged Deployment", utils.AWS, configurations)
	// Working directory will be set dynamically based on uniqueId
	suite.workingDir = "" // Will be set in network stage
}

// TearDownSuite cleans up the test suite
func (suite *StagedDeploymentTestSuite) TearDownSuite() {
	t := suite.T()
	t.Logf("🧹 Starting cleanup stages for: %s", suite.SuiteName)
	suite.testDiskDisabledCleanup()

	suite.testDiskEnabledCleanup()

	test_structure.RunTestStage(t, "cleanup_network", func() {
		// Cleanup network if it was created in this test run
		networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
		if networkOptions := helpers.SafeLoadTerraformOptions(t, networkStageDir); networkOptions != nil {
			t.Logf("🗑️ Cleaning up network...")
			// TODO: fix cleanup when Destroy errors out because Terraform init was not successful during Terraform InitAndApply
			terraform.Destroy(t, networkOptions)
			t.Logf("✅ Network cleanup completed")

			helpers.CleanupTestWorkspace(t, utils.AWS, suite.uniqueId, utils.NetworkingDir)

			// Remove entire state directory since network is the foundation
			t.Logf("🗂️ Removing state directory: %s", suite.workingDir)
			os.RemoveAll(suite.workingDir)
			t.Logf("✅ State directory cleanup completed")
		} else {
			t.Logf("♻️ No network to cleanup (was not created in this test)")
		}
	})

	// S3 backend state files are managed by Terraform and will persist in S3
	// Use S3 lifecycle policies to manage retention if needed

	suite.TearDownBaseSuite()
}

func (suite *StagedDeploymentTestSuite) testDiskEnabledCleanup() {
	t := suite.T()
	t.Log("🧹 Running testDiskEnabled Cleanup (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "cleanup_testDiskEnabled", func() {
		// Cleanup consolidated Materialize stack
		suite.cleanupStage("cleanup_testDiskEnabled", utils.MaterializeDiskEnabledDir)
	})

	t.Logf("✅ testDiskEnabled Cleanup completed successfully")
}

func (suite *StagedDeploymentTestSuite) testDiskDisabledCleanup() {
	t := suite.T()
	t.Log("🧹 Running testDiskDisabled Cleanup (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "cleanup_testDiskDisabled", func() {
		// Cleanup consolidated Materialize stack
		suite.cleanupStage("cleanup_testDiskDisabled", utils.MaterializeDiskDisabledDir)
	})

	t.Logf("✅ testDiskDisabled Cleanup completed successfully")
}

func (suite *StagedDeploymentTestSuite) cleanupStage(stageName, stageDir string) {
	t := suite.T()
	t.Logf("🗑️ Cleaning up %s stage: %s", stageName, stageDir)

	options := helpers.SafeLoadTerraformOptions(t, filepath.Join(suite.workingDir, stageDir))
	if options == nil {
		t.Logf("♻️ No %s stage to cleanup (was not created in this test)", stageName)
		return
	}

	terraform.Destroy(t, options)
	t.Logf("✅ %s stage cleanup completed", stageName)

	// Cleanup workspace
	helpers.CleanupTestWorkspace(t, utils.AWS, suite.uniqueId, stageDir)
}

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → testDiskEnabled/testDiskDisabled
func (suite *StagedDeploymentTestSuite) TestFullDeployment() {
	t := suite.T()
	awsRegion := os.Getenv("AWS_REGION")
	awsProfile := getAWSProfileForTerraform() // Use helper function for OIDC compatibility

	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		var uniqueId string
		if os.Getenv("USE_EXISTING_NETWORK") != "" {
			// Use existing network and initialize S3 backend
			uniqueId = suite.useExistingNetwork()
		} else {
			// Generate unique ID for new infrastructure
			uniqueId = generateAWSCompliantID()
			suite.workingDir = filepath.Join(dir.GetProjectRootDir(), utils.MainTestDir, utils.AWS, uniqueId)
			os.MkdirAll(suite.workingDir, 0755)
			t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
			t.Logf("📁 Test Stage Output directory: %s", suite.workingDir)

			// Save unique ID for subsequent stages
			test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)
			suite.uniqueId = uniqueId

			// Initialize S3 backend manager for new network
			s3Manager, err := initS3BackendManager(t, uniqueId)
			if err != nil {
				t.Fatalf("❌ Failed to initialize S3 backend manager: %v", err)
			}
			suite.s3Manager = s3Manager
		}
		// Set up networking fixture
		networkingPath := helpers.SetupTestWorkspace(t, utils.AWS, uniqueId, utils.NetworkingFixture, utils.NetworkingDir)

		// Create terraform.tfvars.json file for network stage
		networkTfvarsPath := filepath.Join(networkingPath, "terraform.tfvars.json")
		networkVariables := map[string]interface{}{
			"region":               awsRegion,
			"name_prefix":          fmt.Sprintf("%s-net", uniqueId),
			"vpc_cidr":             TestVPCCIDR,
			"availability_zones":   getAvailabilityZones(awsRegion),
			"private_subnet_cidrs": []string{TestPrivateSubnetCIDRA, TestPrivateSubnetCIDRB},
			"public_subnet_cidrs":  []string{TestPublicSubnetCIDRA, TestPublicSubnetCIDRB},
			"single_nat_gateway":   true,
			"create_vpc":           true,
			"tags": map[string]string{
				"environment": helpers.GetEnvironment(),
				"project":     utils.ProjectName,
				"test-run":    uniqueId,
			},
		}

		// Add profile only if it's not empty (for local testing)
		if awsProfile != "" {
			networkVariables["profile"] = awsProfile
		}
		helpers.CreateTfvarsFile(t, networkTfvarsPath, networkVariables)

		networkOptions := &terraform.Options{
			TerraformDir: networkingPath,
			VarFiles:     []string{"terraform.tfvars.json"},
			RetryableTerraformErrors: map[string]string{
				"RequestError": "Request failed",
			},
			MaxRetries:         TestMaxRetries,
			TimeBetweenRetries: TestRetryDelay,
			NoColor:            true,
		}

		// Configure S3 backend if enabled - Terraform will handle state management
		applyBackendConfigToTerraformOptions(networkOptions, suite.s3Manager, utils.NetworkingDir)

		// Save terraform options for potential cleanup stage
		networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
		test_structure.SaveTerraformOptions(t, networkStageDir, networkOptions)

		// Apply
		terraform.InitAndApply(t, networkOptions)

		// Save all networking outputs for subsequent stages
		vpcId := terraform.Output(t, networkOptions, "vpc_id")
		privateSubnetIds := terraform.OutputList(t, networkOptions, "private_subnet_ids")
		publicSubnetIds := terraform.OutputList(t, networkOptions, "public_subnet_ids")

		// Save all outputs and resource IDs to networking directory
		test_structure.SaveString(t, networkStageDir, "vpc_id", vpcId)
		test_structure.SaveString(t, networkStageDir, "private_subnet_ids", strings.Join(privateSubnetIds, ","))
		test_structure.SaveString(t, networkStageDir, "public_subnet_ids", strings.Join(publicSubnetIds, ","))

		t.Logf("✅ Network infrastructure created:")
		t.Logf("  🌐 VPC: %s", vpcId)
		t.Logf("  🔒 Private Subnets: %v", privateSubnetIds)
		t.Logf("  🌍 Public Subnets: %v", publicSubnetIds)
		t.Logf("  🏷️ Resource ID: %s", uniqueId)

	})

	// If network stage was skipped, use existing network
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Stage 2: testDiskEnabled (EKS + Database + Materialize)
	suite.testDiskEnabled(awsProfile, awsRegion)

	// Stage 3: testDiskDisabled (EKS + Database + Materialize)
	suite.testDiskDisabled(awsProfile, awsRegion)
}

// testDiskEnabled deploys the complete Materialize stack with disk enabled
func (suite *StagedDeploymentTestSuite) testDiskEnabled(awsProfile, awsRegion string) {
	t := suite.T()
	t.Log("🚀 Running testDiskEnabled (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "testDiskEnabled", func() {
		suite.setupMaterializeConsolidatedStage("testDiskEnabled", utils.MaterializeDiskEnabledDir,
			awsProfile, awsRegion, utils.DiskEnabledShortSuffix, true, TestEKSDiskEnabledInstanceType)
	})

	t.Logf("✅ testDiskEnabled completed successfully")
}

// testDiskDisabled deploys the complete Materialize stack with disk disabled
func (suite *StagedDeploymentTestSuite) testDiskDisabled(awsProfile, awsRegion string) {
	t := suite.T()
	t.Log("🚀 Running testDiskDisabled (Complete Materialize Stack)")

	test_structure.RunTestStage(t, "testDiskDisabled", func() {
		suite.setupMaterializeConsolidatedStage("testDiskDisabled", utils.MaterializeDiskDisabledDir,
			awsProfile, awsRegion, utils.DiskDisabledShortSuffix, false, TestEKSDiskDisabledInstanceType)
	})

	t.Logf("✅ testDiskDisabled completed successfully")
}

// setupMaterializeConsolidatedStage deploys the complete Materialize stack (EKS + Database + Materialize)
func (suite *StagedDeploymentTestSuite) setupMaterializeConsolidatedStage(stage, stageDir, profile, region, nameSuffix string, diskEnabled bool, instanceType string) {
	t := suite.T()
	t.Logf("🔧 Setting up consolidated Materialize stage: %s", stage)

	// Ensure workingDir is set
	if suite.workingDir == "" {
		t.Fatal("❌ Cannot create Materialize stack: Working directory not set. Run network setup stage first.")
	}

	// Load saved network data
	networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
	vpcId := test_structure.LoadString(t, networkStageDir, "vpc_id")
	privateSubnetIdsStr := test_structure.LoadString(t, networkStageDir, "private_subnet_ids")

	// Parse private subnet IDs from comma-separated string
	privateSubnetIds := strings.Split(privateSubnetIdsStr, ",")

	// Validate required network data exists
	if vpcId == "" || len(privateSubnetIds) == 0 || privateSubnetIds[0] == "" || suite.uniqueId == "" {
		t.Fatal("❌ Cannot create Materialize stack: Missing network data. Run network setup stage first.")
	}

	t.Logf("🔗 Using infrastructure family: %s", suite.uniqueId)

	// Set up consolidated Materialize fixture
	materializePath := helpers.SetupTestWorkspace(t, utils.AWS, suite.uniqueId, utils.MaterializeFixture, stageDir)

	expectedInstanceNamespace := fmt.Sprintf("mz-instance-%s", nameSuffix)
	expectedOperatorNamespace := fmt.Sprintf("mz-operator-%s", nameSuffix)
	expectedCertManagerNamespace := fmt.Sprintf("cert-manager-%s", nameSuffix)
	resourceName := fmt.Sprintf("%s%s", suite.uniqueId, nameSuffix)

	// Create terraform.tfvars.json file instead of using Vars map
	// This approach is cleaner and follows Terraform best practices
	tfvarsPath := filepath.Join(materializePath, "terraform.tfvars.json")

	// Build variables map for the generic tfvars creation function
	variables := map[string]interface{}{
		// AWS Configuration
		"region": region,

		// Network Configuration
		"vpc_id":     vpcId,
		"subnet_ids": privateSubnetIds,

		// Resource Naming
		"name_prefix": resourceName,

		// EKS Configuration
		"cluster_version":                          TestKubernetesVersion,
		"cluster_enabled_log_types":                []string{"api", "audit"},
		"enable_cluster_creator_admin_permissions": true,
		"min_nodes":                                1,
		"max_nodes":                                3,
		"desired_nodes":                            2,
		"instance_types":                           []string{instanceType},
		"capacity_type":                            "ON_DEMAND",
		"swap_enabled":                             diskEnabled,
		"iam_role_use_name_prefix":                 false,

		// Node Labels
		"node_labels": map[string]string{
			"environment":            helpers.GetEnvironment(),
			"project":                utils.ProjectName,
			"materialize.cloud/disk": fmt.Sprintf("%t", diskEnabled),
		},

		// Database Configuration
		"postgres_version":        TestPostgreSQLVersion,
		"instance_class":          TestRDSInstanceClassSmall,
		"allocated_storage":       TestAllocatedStorageSmall,
		"max_allocated_storage":   TestMaxAllocatedStorageSmall,
		"multi_az":                false,
		"database_name":           TestDBName,
		"database_username":       TestDBUsername,
		"database_password":       TestPassword,
		"maintenance_window":      TestMaintenanceWindow,
		"backup_window":           TestBackupWindow,
		"backup_retention_period": TestBackupRetentionPeriod,

		// S3 Configuration
		"bucket_lifecycle_rules":   []interface{}{},
		"bucket_force_destroy":     true,
		"enable_bucket_versioning": false,
		"enable_bucket_encryption": false,

		// Cert Manager Configuration
		"cert_manager_install_timeout": 600,
		"cert_manager_chart_version":   TestCertManagerVersion,
		"cert_manager_namespace":       expectedCertManagerNamespace,

		// Operator Configuration
		"operator_namespace": expectedOperatorNamespace,

		// Materialize Instance Configuration
		"instance_name":                     fmt.Sprintf("%s-%s", suite.uniqueId, nameSuffix),
		"instance_namespace":                expectedInstanceNamespace,
		"external_login_password_mz_system": TestPassword,
		"license_key":                       os.Getenv("MATERIALIZE_LICENSE_KEY"),

		// NLB Configuration
		"enable_cross_zone_load_balancing": true,

		// Tags
		"tags": map[string]string{
			"environment":  helpers.GetEnvironment(),
			"project":      utils.ProjectName,
			"test-run":     suite.uniqueId,
			"disk-enabled": fmt.Sprintf("%t", diskEnabled),
		},
	}

	// Add profile only if it's not empty (for local testing)
	if profile != "" {
		variables["profile"] = profile
	}

	helpers.CreateTfvarsFile(t, tfvarsPath, variables)
	materializeOptions := &terraform.Options{
		TerraformDir: materializePath,
		VarFiles:     []string{"terraform.tfvars.json"},
		RetryableTerraformErrors: map[string]string{
			"RequestError":              "Request failed",
			"InvalidParameterException": "EKS service error",
		},
		MaxRetries:         TestMaxRetries,
		TimeBetweenRetries: TestRetryDelay,
		NoColor:            true,
	}

	// Configure S3 backend if enabled - Terraform will handle state management
	applyBackendConfigToTerraformOptions(materializeOptions, suite.s3Manager, stageDir)

	// Save terraform options for cleanup
	stageDirPath := filepath.Join(suite.workingDir, stageDir)
	test_structure.SaveTerraformOptions(t, stageDirPath, materializeOptions)

	// Apply
	terraform.InitAndApply(t, materializeOptions)

	// Validate all outputs from the consolidated fixture
	t.Log("🔍 Validating all consolidated fixture outputs...")

	// EKS Cluster Outputs
	clusterName := terraform.Output(t, materializeOptions, "cluster_name")
	clusterEndpoint := terraform.Output(t, materializeOptions, "cluster_endpoint")
	clusterCertificateAuthorityData := terraform.Output(t, materializeOptions, "cluster_certificate_authority_data")
	clusterOidcIssuerUrl := terraform.Output(t, materializeOptions, "cluster_oidc_issuer_url")
	oidcProviderArn := terraform.Output(t, materializeOptions, "oidc_provider_arn")
	clusterIamRoleName := terraform.Output(t, materializeOptions, "cluster_iam_role_name")

	// EKS Security Outputs
	clusterSecurityGroupId := terraform.Output(t, materializeOptions, "cluster_security_group_id")
	nodeSecurityGroupId := terraform.Output(t, materializeOptions, "node_security_group_id")
	clusterServiceCidr := terraform.Output(t, materializeOptions, "cluster_service_cidr")

	// Database Outputs
	databaseEndpoint := terraform.Output(t, materializeOptions, "database_endpoint")
	databasePort := terraform.Output(t, materializeOptions, "database_port")
	databaseName := terraform.Output(t, materializeOptions, "database_name")
	databaseUsername := terraform.Output(t, materializeOptions, "database_username")
	databaseIdentifier := terraform.Output(t, materializeOptions, "database_identifier")
	databaseSecurityGroupId := terraform.Output(t, materializeOptions, "database_security_group_id")

	// S3 Storage Outputs
	s3BucketName := terraform.Output(t, materializeOptions, "s3_bucket_name")
	s3BucketArn := terraform.Output(t, materializeOptions, "s3_bucket_arn")
	s3BucketDomainName := terraform.Output(t, materializeOptions, "s3_bucket_domain_name")
	materializeS3RoleArn := terraform.Output(t, materializeOptions, "materialize_s3_role_arn")

	// Materialize Backend URLs
	metadataBackendUrl := terraform.Output(t, materializeOptions, "metadata_backend_url")
	persistBackendUrl := terraform.Output(t, materializeOptions, "persist_backend_url")

	// Materialize Operator Outputs
	operatorNamespace := terraform.Output(t, materializeOptions, "operator_namespace")
	operatorReleaseName := terraform.Output(t, materializeOptions, "operator_release_name")
	operatorReleaseStatus := terraform.Output(t, materializeOptions, "operator_release_status")

	// Materialize Instance Outputs
	instanceResourceId := terraform.Output(t, materializeOptions, "instance_resource_id")

	// Network Load Balancer Outputs
	nlbDetails := terraform.OutputMap(t, materializeOptions, "nlb_details")
	nlbArn := nlbDetails["arn"]
	nlbDnsName := nlbDetails["dns_name"]

	// Certificate Outputs
	clusterIssuerName := terraform.Output(t, materializeOptions, "cluster_issuer_name")

	// Comprehensive validation
	t.Log("✅ Validating EKS Cluster Outputs...")
	suite.NotEmpty(clusterName, "Cluster name should not be empty")
	suite.Contains(clusterName, suite.uniqueId, "Cluster name should contain resource ID")
	suite.Contains(clusterEndpoint, "eks.amazonaws.com", "Cluster endpoint should be valid EKS endpoint")
	suite.NotEmpty(clusterCertificateAuthorityData, "Cluster certificate authority data should not be empty")
	suite.NotEmpty(clusterOidcIssuerUrl, "Cluster OIDC issuer URL should not be empty")
	suite.NotEmpty(oidcProviderArn, "OIDC provider ARN should not be empty")
	suite.NotEmpty(clusterIamRoleName, "Cluster IAM role name should not be empty")

	t.Log("✅ Validating EKS Security Outputs...")
	suite.NotEmpty(clusterSecurityGroupId, "Cluster security group ID should not be empty")
	suite.NotEmpty(nodeSecurityGroupId, "Node security group ID should not be empty")
	suite.NotEmpty(clusterServiceCidr, "Cluster service CIDR should not be empty")

	t.Log("✅ Validating Database Outputs...")
	suite.Contains(databaseEndpoint, ".rds.amazonaws.com", "Database endpoint should be a valid RDS endpoint")
	suite.Equal("5432", databasePort, "Database port should be 5432")
	suite.NotEmpty(databaseName, "Database name should not be empty")
	suite.NotEmpty(databaseUsername, "Database username should not be empty")
	suite.NotEmpty(databaseIdentifier, "Database identifier should not be empty")
	suite.NotEmpty(databaseSecurityGroupId, "Database security group ID should not be empty")

	t.Log("✅ Validating S3 Storage Outputs...")
	suite.NotEmpty(s3BucketName, "S3 bucket name should not be empty")
	suite.NotEmpty(s3BucketArn, "S3 bucket ARN should not be empty")
	suite.NotEmpty(s3BucketDomainName, "S3 bucket domain name should not be empty")
	suite.NotEmpty(materializeS3RoleArn, "Materialize S3 role ARN should not be empty")

	t.Log("✅ Validating Materialize Backend URLs...")
	suite.NotEmpty(metadataBackendUrl, "Metadata backend URL should not be empty")
	suite.NotEmpty(persistBackendUrl, "Persist backend URL should not be empty")

	t.Log("✅ Validating Materialize Operator Outputs...")
	suite.NotEmpty(operatorNamespace, "Operator namespace should not be empty")
	suite.NotEmpty(operatorReleaseName, "Operator release name should not be empty")
	suite.NotEmpty(operatorReleaseStatus, "Operator release status should not be empty")

	t.Log("✅ Validating Materialize Instance Outputs...")
	suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")

	t.Log("✅ Validating Network Load Balancer Outputs...")
	suite.NotEmpty(nlbArn, "NLB ARN should not be empty")
	suite.NotEmpty(nlbDnsName, "NLB DNS name should not be empty")

	t.Log("✅ Validating Certificate Outputs...")
	suite.NotEmpty(clusterIssuerName, "Cluster issuer name should not be empty")

	t.Logf("✅ Complete Materialize stack created successfully:")
	t.Logf("  💾 Disk Enabled: %t", diskEnabled)

	// EKS Cluster Outputs
	t.Logf("🔧 EKS CLUSTER OUTPUTS:")
	t.Logf("  📛 Cluster Name: %s", clusterName)
	t.Logf("  🔗 Cluster Endpoint: %s", clusterEndpoint)
	t.Logf("  📜 Cluster Certificate Authority Data: %s", clusterCertificateAuthorityData)
	t.Logf("  🌐 Cluster OIDC Issuer URL: %s", clusterOidcIssuerUrl)
	t.Logf("  🆔 OIDC Provider ARN: %s", oidcProviderArn)
	t.Logf("  👤 Cluster IAM Role Name: %s", clusterIamRoleName)

	// EKS Security Outputs
	t.Logf("🔒 EKS SECURITY OUTPUTS:")
	t.Logf("  🛡️ Cluster Security Group ID: %s", clusterSecurityGroupId)
	t.Logf("  🛡️ Node Security Group ID: %s", nodeSecurityGroupId)
	t.Logf("  🌐 Cluster Service CIDR: %s", clusterServiceCidr)

	// Database Outputs
	t.Logf("🗄️ DATABASE OUTPUTS:")
	t.Logf("  🔗 Database Endpoint: %s", databaseEndpoint)
	t.Logf("  🔌 Database Port: %s", databasePort)
	t.Logf("  📛 Database Name: %s", databaseName)
	t.Logf("  👤 Database Username: %s", databaseUsername)
	t.Logf("  🏷️ Database Identifier: %s", databaseIdentifier)
	t.Logf("  🛡️ Database Security Group ID: %s", databaseSecurityGroupId)

	// S3 Storage Outputs
	t.Logf("☁️ S3 STORAGE OUTPUTS:")
	t.Logf("  🪣 S3 Bucket Name: %s", s3BucketName)
	t.Logf("  🪣 S3 Bucket ARN: %s", s3BucketArn)
	t.Logf("  🌐 S3 Bucket Domain Name: %s", s3BucketDomainName)
	t.Logf("  👤 Materialize S3 Role ARN: %s", materializeS3RoleArn)

	// Materialize Backend URLs
	t.Logf("🔗 MATERIALIZE BACKEND URLS:")
	t.Logf("  🗄️ Metadata Backend URL: %s", metadataBackendUrl)
	t.Logf("  💾 Persist Backend URL: %s", persistBackendUrl)

	// Materialize Operator Outputs
	t.Logf("⚙️ MATERIALIZE OPERATOR OUTPUTS:")
	t.Logf("  📦 Operator Namespace: %s", operatorNamespace)
	t.Logf("  📦 Operator Release Name: %s", operatorReleaseName)
	t.Logf("  📊 Operator Release Status: %s", operatorReleaseStatus)

	// Materialize Instance Outputs
	t.Logf("🚀 MATERIALIZE INSTANCE OUTPUTS:")
	t.Logf("  🆔 Instance Resource ID: %s", instanceResourceId)

	// Network Load Balancer Outputs
	t.Logf("🌐 NETWORK LOAD BALANCER OUTPUTS:")
	t.Logf("  🆔 NLB ARN: %s", nlbArn)
	t.Logf("  🌐 NLB DNS Name: %s", nlbDnsName)

	// Certificate Outputs
	t.Logf("🔐 CERTIFICATE OUTPUTS:")
	t.Logf("  📜 Cluster Issuer Name: %s", clusterIssuerName)

}

func (suite *StagedDeploymentTestSuite) useExistingNetwork() string {
	t := suite.T()
	testCloudDir := filepath.Join(dir.GetProjectRootDir(), utils.MainTestDir, utils.AWS)
	lastRunDir, err := dir.GetLastRunTestStageDir(testCloudDir)
	if err != nil {
		t.Fatalf("Unable to use existing network %v", err)
	}
	// Use the full path returned by the helper
	suite.workingDir = lastRunDir

	// Load and return the unique ID
	uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
	if uniqueId == "" {
		t.Fatal("❌ Cannot use existing network: Unique ID not found. Run network setup stage first.")
	}
	suite.uniqueId = uniqueId

	// Validate that network was created successfully by checking VPC ID
	networkStageDir := filepath.Join(suite.workingDir, utils.NetworkingDir)
	vpcID := test_structure.LoadString(t, networkStageDir, "vpc_id")
	latestDir := filepath.Base(lastRunDir)
	if vpcID == "" {
		t.Fatalf("❌ Cannot skip network creation: VPC ID is empty in state directory %s", latestDir)
	}

	// Initialize S3 backend manager for existing network
	s3Manager, err := initS3BackendManager(t, uniqueId)
	if err != nil {
		t.Fatalf("❌ Failed to initialize S3 backend manager: %v", err)
	}
	suite.s3Manager = s3Manager

	t.Logf("♻️ Using existing network from: %s (ID: %s, VPC: %s)", suite.workingDir, uniqueId, vpcID)
	return uniqueId
}

// TestStagedDeploymentSuite runs the staged deployment test suite
func TestStagedDeploymentSuite(t *testing.T) {
	// Run the test suite
	suite.Run(t, new(StagedDeploymentTestSuite))
}
