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
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/suite"
)

// StagedDeploymentTestSuite tests the full AWS infrastructure deployment in stages
type StagedDeploymentTestSuite struct {
	basesuite.BaseTestSuite
	workingDir string
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

	test_structure.RunTestStage(t, "cleanup_materialize_disk_enabled", func() {
		// Only cleanup if Materialize was created in this test run
		diskEnabledTestOptionsPath := filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir)
		if materializeOptions := test_structure.LoadTerraformOptions(t, diskEnabledTestOptionsPath); materializeOptions != nil {
			t.Logf("🗑️ Cleaning up Materialize (disk-enabled)...")
			terraform.Destroy(t, materializeOptions)
			t.Logf("✅ Materialize (disk-enabled) cleanup completed")
			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId, utils.MaterializeDiskEnabledDir)
		} else {
			t.Logf("♻️ No Materialize (disk-enabled) to cleanup (was not created in this test)")
		}
	})

	// Cleanup stages (run in reverse order: Database, EKS clusters, then network)
	test_structure.RunTestStage(t, "cleanup_database", func() {
		// Only cleanup if database was created in this test run
		if dbOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/database"); dbOptions != nil {
			t.Logf("🗑️ Cleaning up database...")
			terraform.Destroy(t, dbOptions)
			t.Logf("✅ Database cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId, utils.DataBaseDir)
		} else {
			t.Logf("♻️ No database to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_eks_disk_disabled", func() {
		// Cleanup EKS disk-disabled cluster if it was created in this test run
		if eksOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/eks-disk-disabled"); eksOptions != nil {
			t.Logf("🗑️ Cleaning up EKS cluster (disk-disabled)...")
			terraform.Destroy(t, eksOptions)
			t.Logf("✅ EKS cluster (disk-disabled) cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId, utils.EKSDiskDisabledDir)
		} else {
			t.Logf("♻️ No EKS cluster (disk-disabled) to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_eks_disk_enabled", func() {
		// Cleanup EKS disk-enabled cluster if it was created in this test run
		if eksOptions := test_structure.LoadTerraformOptions(t, suite.workingDir+"/eks-disk-enabled"); eksOptions != nil {
			t.Logf("🗑️ Cleaning up EKS cluster (disk-enabled)...")
			terraform.Destroy(t, eksOptions)
			t.Logf("✅ EKS cluster (disk-enabled) cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId, utils.EKSDiskEnabledDir)
		} else {
			t.Logf("♻️ No EKS cluster (disk-enabled) to cleanup (was not created in this test)")
		}
	})

	test_structure.RunTestStage(t, "cleanup_network", func() {
		// Cleanup network if it was created in this test run
		if networkOptions := test_structure.LoadTerraformOptions(t, suite.workingDir); networkOptions != nil {
			t.Logf("🗑️ Cleaning up network...")
			terraform.Destroy(t, networkOptions)
			t.Logf("✅ Network cleanup completed")

			uniqueId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")
			helpers.CleanupTestWorkspace(t, utils.AWS, uniqueId, utils.NetworkingDir)

			// Remove entire state directory since network is the foundation
			t.Logf("🗂️ Removing state directory: %s", suite.workingDir)
			os.RemoveAll(suite.workingDir)
			t.Logf("✅ State directory cleanup completed")
		} else {
			t.Logf("♻️ No network to cleanup (was not created in this test)")
		}
	})
	suite.TearDownBaseSuite()
}

// TestFullDeployment tests full infrastructure deployment
// Stages: Network → EKS (disk-enabled) → EKS (disk-disabled) → Database
func (suite *StagedDeploymentTestSuite) TestFullDeployment() {
	t := suite.T()
	awsRegion := os.Getenv("AWS_REGION")
	awsProfile := os.Getenv("AWS_PROFILE")
	// Stage 1: Network Setup
	test_structure.RunTestStage(t, "setup_network", func() {
		// Generate unique ID for this infrastructure family
		if os.Getenv("USE_EXISTING_NETWORK") != "" {
			suite.useExistingNetwork()
		} else {
			uniqueId := generateAWSCompliantID()
			suite.workingDir = fmt.Sprintf("%s/%s", TestRunsDir, uniqueId)
			os.MkdirAll(suite.workingDir, 0755)
			t.Logf("🏷️ Infrastructure ID: %s", uniqueId)
			t.Logf("📁 Test Stage Output directory: %s", suite.workingDir)

			// Set up networking example
			networkingPath := helpers.SetupTestWorkspace(t, utils.AWS, uniqueId, utils.NetworkingDir, utils.NetworkingDir)

			networkOptions := &terraform.Options{
				TerraformDir: networkingPath,
				Vars: map[string]interface{}{
					"profile":              awsProfile,
					"region":               awsRegion,
					"name_prefix":          fmt.Sprintf("%s-net", uniqueId),
					"vpc_cidr":             TestVPCCIDR,
					"availability_zones":   []string{TestAvailabilityZoneA, TestAvailabilityZoneB},
					"private_subnet_cidrs": []string{TestPrivateSubnetCIDRA, TestPrivateSubnetCIDRB},
					"public_subnet_cidrs":  []string{TestPublicSubnetCIDRA, TestPublicSubnetCIDRB},
					"single_nat_gateway":   true,
					"create_vpc":           true,
					"tags": map[string]string{
						"Environment": "test",
						"Project":     "materialize",
						"TestRun":     uniqueId,
					},
				},
				RetryableTerraformErrors: map[string]string{
					"RequestError": "Request failed",
				},
				MaxRetries:         TestMaxRetries,
				TimeBetweenRetries: TestRetryDelay,
				NoColor:            true,
			}

			// Save terraform options for potential cleanup stage
			test_structure.SaveTerraformOptions(t, suite.workingDir, networkOptions)

			// Apply
			terraform.InitAndApply(t, networkOptions)

			// Save all networking outputs for subsequent stages
			vpcId := terraform.Output(t, networkOptions, "vpc_id")
			privateSubnetIds := terraform.OutputList(t, networkOptions, "private_subnet_ids")
			publicSubnetIds := terraform.OutputList(t, networkOptions, "public_subnet_ids")

			// Save all outputs and resource IDs
			test_structure.SaveString(t, suite.workingDir, "vpc_id", vpcId)
			test_structure.SaveString(t, suite.workingDir, "resource_unique_id", uniqueId)
			test_structure.SaveString(t, suite.workingDir, "private_subnet_ids", strings.Join(privateSubnetIds, ","))
			test_structure.SaveString(t, suite.workingDir, "public_subnet_ids", strings.Join(publicSubnetIds, ","))

			t.Logf("✅ Network infrastructure created:")
			t.Logf("  🌐 VPC: %s", vpcId)
			t.Logf("  🔒 Private Subnets: %v", privateSubnetIds)
			t.Logf("  🌍 Public Subnets: %v", publicSubnetIds)
			t.Logf("  🏷️ Resource ID: %s", uniqueId)
		}
	})
	if os.Getenv("SKIP_setup_network") != "" {
		suite.useExistingNetwork()
	}

	// Stage 2: EKS Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_eks_disk_enabled", func() {
		// Ensure workingDir is set
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot create EKS: Working directory not set. Run network setup stage first.")
		}

		// Load saved network data
		vpcId := test_structure.LoadString(t, suite.workingDir, "vpc_id")
		privateSubnetIdsStr := test_structure.LoadString(t, suite.workingDir, "private_subnet_ids")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

		// Parse private subnet IDs from comma-separated string
		privateSubnetIds := strings.Split(privateSubnetIdsStr, ",")

		// Validate required network data exists
		if vpcId == "" || len(privateSubnetIds) == 0 || privateSubnetIds[0] == "" || resourceId == "" {
			t.Fatal("❌ Cannot create EKS: Missing network data. Run network setup stage first.")
		}

		t.Logf("🔗 Using infrastructure family: %s", resourceId)

		// Set up EKS example with disk enabled
		eksPath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId, utils.EKSDir, utils.EKSDiskEnabledDir)

		eksOptions := &terraform.Options{
			TerraformDir: eksPath,
			Vars: map[string]interface{}{
				"profile":                   awsProfile,
				"region":                    awsRegion,
				"cluster_name":              fmt.Sprintf("%sdisk", resourceId),
				"cluster_version":           TestKubernetesVersion,
				"vpc_id":                    vpcId,
				"subnet_ids":                privateSubnetIds,
				"cluster_enabled_log_types": []string{"api", "audit"},
				"enable_cluster_creator_admin_permissions": true,
				"skip_node_group":                          false,
				"skip_aws_lbc":                             false,
				"min_nodes":                                1,
				"max_nodes":                                3,
				"desired_nodes":                            2,
				"instance_types":                           []string{TestEKSDiskEnabledInstanceType},
				"capacity_type":                            "ON_DEMAND",
				"disk_setup_enabled":                       true,
				"iam_role_use_name_prefix":                 false,
				"node_labels": map[string]string{
					"Environment":            "test",
					"Project":                "materialize",
					"materialize.cloud/disk": "true",
					"workload":               "materialize-instance",
				},
				"tags": map[string]string{
					"Environment": "test",
					"Project":     "materialize",
					"TestRun":     resourceId,
					"DiskEnabled": "true",
				},
			},
			RetryableTerraformErrors: map[string]string{
				"RequestError":              "Request failed",
				"InvalidParameterException": "EKS service error",
			},
			MaxRetries:         TestMaxRetries,
			TimeBetweenRetries: TestRetryDelay,
			NoColor:            true,
		}

		// Save terraform options for cleanup
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/eks-disk-enabled", eksOptions)

		// Apply
		terraform.InitAndApply(t, eksOptions)

		// Save EKS outputs for subsequent stages
		clusterName := terraform.Output(t, eksOptions, "cluster_name")
		clusterEndpoint := terraform.Output(t, eksOptions, "cluster_endpoint")
		clusterSecurityGroupId := terraform.Output(t, eksOptions, "cluster_security_group_id")
		nodeSecurityGroupId := terraform.Output(t, eksOptions, "node_security_group_id")
		oidcProviderArn := terraform.Output(t, eksOptions, "oidc_provider_arn")
		clusterServiceCIDR := terraform.Output(t, eksOptions, "cluster_service_cidr")
		clusterOidcIssuerUrl := terraform.Output(t, eksOptions, "cluster_oidc_issuer_url")
		clusterCertificateAuthorityData := terraform.Output(t, eksOptions, "cluster_certificate_authority_data")

		// Validate outputs
		suite.NotEmpty(clusterName, "Cluster name should not be empty")
		suite.Contains(clusterName, resourceId, "Cluster name should contain resource ID")
		suite.Contains(clusterEndpoint, "eks.amazonaws.com", "Cluster endpoint should be valid EKS endpoint")
		suite.NotEmpty(clusterSecurityGroupId, "Cluster security group ID should not be empty")
		suite.NotEmpty(nodeSecurityGroupId, "Node security group ID should not be empty")
		suite.NotEmpty(oidcProviderArn, "OIDC provider ARN should not be empty")
		suite.NotEmpty(clusterServiceCIDR, "Cluster service CIDR should not be empty")
		suite.NotEmpty(clusterOidcIssuerUrl, "Cluster OIDC issuer URL should not be empty")
		suite.NotEmpty(clusterCertificateAuthorityData, "Cluster certificate authority data should not be empty")

		// Save all outputs with disk-enabled suffix
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "cluster_name", clusterName)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "cluster_endpoint", clusterEndpoint)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "cluster_security_group_id", clusterSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "node_security_group_id", nodeSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "oidc_provider_arn", oidcProviderArn)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "cluster_oidc_issuer_url", clusterOidcIssuerUrl)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "cluster_service_cidr", clusterServiceCIDR)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "cluster_certificate_authority_data", clusterCertificateAuthorityData)

		// Save generic security group IDs for database stage
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "cluster_security_group_id", clusterSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-enabled", "node_security_group_id", nodeSecurityGroupId)

		// TODO add checks to ensure disk setup is enabled
		// use vgs/ pvs commands and verify the output

		t.Logf("✅ EKS cluster (disk-enabled) created successfully:")
		t.Logf("  📛 Cluster Name: %s", clusterName)
		t.Logf("  🔗 Endpoint: %s", clusterEndpoint)
		t.Logf("  🔒 Cluster Security Group: %s", clusterSecurityGroupId)
		t.Logf("  🔒 Node Security Group: %s", nodeSecurityGroupId)
		t.Logf("  🆔 OIDC Provider: %s", oidcProviderArn)
		t.Logf("  💾 Disk Enabled: true")
		t.Logf("  🌐 Cluster Service CIDR: %s", clusterServiceCIDR)
		t.Logf("  🌐 Cluster OIDC Issuer URL: %s", clusterOidcIssuerUrl)
		t.Logf("  📜 Cluster Certificate Authority Data: %s", clusterCertificateAuthorityData)

	})

	// Stage 3: EKS Setup (Disk Disabled)
	test_structure.RunTestStage(t, "setup_eks_disk_disabled", func() {
		// Ensure workingDir is set
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot create EKS: Working directory not set. Run network setup stage first.")
		}

		// Load saved network data
		vpcId := test_structure.LoadString(t, suite.workingDir, "vpc_id")
		privateSubnetIdsStr := test_structure.LoadString(t, suite.workingDir, "private_subnet_ids")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

		// Parse private subnet IDs from comma-separated string
		privateSubnetIds := strings.Split(privateSubnetIdsStr, ",")

		// Validate required network data exists
		if vpcId == "" || len(privateSubnetIds) == 0 || privateSubnetIds[0] == "" || resourceId == "" {
			t.Fatal("❌ Cannot create EKS: Missing network data. Run network setup stage first.")
		}

		t.Logf("🔗 Using infrastructure family: %s", resourceId)

		// Set up EKS example with disk disabled
		eksPath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId, utils.EKSDir, utils.EKSDiskDisabledDir)

		eksOptions := &terraform.Options{
			TerraformDir: eksPath,
			Vars: map[string]interface{}{
				"profile":                   awsProfile,
				"region":                    awsRegion,
				"cluster_name":              fmt.Sprintf("%snodisk", resourceId),
				"cluster_version":           TestKubernetesVersion,
				"vpc_id":                    vpcId,
				"subnet_ids":                privateSubnetIds,
				"cluster_enabled_log_types": []string{"api", "audit"},
				"enable_cluster_creator_admin_permissions": true,
				"skip_node_group":                          false,
				"skip_aws_lbc":                             false,
				"min_nodes":                                1,
				"max_nodes":                                3,
				"desired_nodes":                            2,
				"instance_types":                           []string{TestEKSDiskDisabledInstanceType},
				"capacity_type":                            "ON_DEMAND",
				"disk_setup_enabled":                       false,
				"iam_role_use_name_prefix":                 false,
				"node_labels": map[string]string{
					"Environment":            "test",
					"Project":                "materialize",
					"materialize.cloud/disk": "false",
					"workload":               "materialize-instance",
				},
				"tags": map[string]string{
					"Environment": "test",
					"Project":     "materialize",
					"TestRun":     resourceId,
					"DiskEnabled": "false",
				},
			},
			RetryableTerraformErrors: map[string]string{
				"RequestError":              "Request failed",
				"InvalidParameterException": "EKS service error",
			},
			MaxRetries:         TestMaxRetries,
			TimeBetweenRetries: TestRetryDelay,
			NoColor:            true,
		}

		// Save terraform options for cleanup
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/eks-disk-disabled", eksOptions)

		// Apply
		terraform.InitAndApply(t, eksOptions)

		// Save EKS outputs for subsequent stages
		clusterName := terraform.Output(t, eksOptions, "cluster_name")
		clusterEndpoint := terraform.Output(t, eksOptions, "cluster_endpoint")
		clusterSecurityGroupId := terraform.Output(t, eksOptions, "cluster_security_group_id")
		nodeSecurityGroupId := terraform.Output(t, eksOptions, "node_security_group_id")
		oidcProviderArn := terraform.Output(t, eksOptions, "oidc_provider_arn")
		clusterServiceCIDR := terraform.Output(t, eksOptions, "cluster_service_cidr")
		clusterOidcIssuerUrl := terraform.Output(t, eksOptions, "cluster_oidc_issuer_url")
		clusterCertificateAuthorityData := terraform.Output(t, eksOptions, "cluster_certificate_authority_data")

		// Save all outputs with disk-disabled suffix
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-disabled", "cluster_name", clusterName)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-disabled", "cluster_endpoint", clusterEndpoint)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-disabled", "cluster_security_group_id", clusterSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-disabled", "node_security_group_id", nodeSecurityGroupId)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-disabled", "oidc_provider_arn", oidcProviderArn)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-disabled", "cluster_oidc_issuer_url", clusterOidcIssuerUrl)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-disabled", "cluster_service_cidr", clusterServiceCIDR)
		test_structure.SaveString(t, suite.workingDir+"/eks-disk-disabled", "cluster_certificate_authority_data", clusterCertificateAuthorityData)

		// Validate outputs
		suite.NotEmpty(clusterName, "Cluster name should not be empty")
		suite.Contains(clusterName, resourceId, "Cluster name should contain resource ID")
		suite.Contains(clusterEndpoint, "eks.amazonaws.com", "Cluster endpoint should be valid EKS endpoint")
		suite.NotEmpty(clusterSecurityGroupId, "Cluster security group ID should not be empty")
		suite.NotEmpty(nodeSecurityGroupId, "Node security group ID should not be empty")
		suite.NotEmpty(oidcProviderArn, "OIDC provider ARN should not be empty")
		suite.NotEmpty(clusterServiceCIDR, "Cluster service CIDR should not be empty")
		suite.NotEmpty(clusterOidcIssuerUrl, "Cluster OIDC issuer URL should not be empty")
		suite.NotEmpty(clusterCertificateAuthorityData, "Cluster certificate authority data should not be empty")

		t.Logf("✅ EKS cluster (disk-disabled) created successfully:")
		t.Logf("  📛 Cluster Name: %s", clusterName)
		t.Logf("  🔗 Endpoint: %s", clusterEndpoint)
		t.Logf("  🔒 Cluster Security Group: %s", clusterSecurityGroupId)
		t.Logf("  🔒 Node Security Group: %s", nodeSecurityGroupId)
		t.Logf("  🆔 OIDC Provider: %s", oidcProviderArn)
		t.Logf("  💾 Disk Enabled: false")
		t.Logf("  🌐 Cluster Service CIDR: %s", clusterServiceCIDR)
		t.Logf("  🌐 Cluster OIDC Issuer URL: %s", clusterOidcIssuerUrl)
		t.Logf("  📜 Cluster Certificate Authority Data: %s", clusterCertificateAuthorityData)
	})

	// Stage 4: Database Setup
	test_structure.RunTestStage(t, "setup_database", func() {
		// Ensure workingDir is set (should be set by network stage)
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot create database: Working directory not set. Run network setup stage first.")
		}

		// Load saved network data with validation
		vpcId := test_structure.LoadString(t, suite.workingDir, "vpc_id")
		privateSubnetIdsStr := test_structure.LoadString(t, suite.workingDir, "private_subnet_ids")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

		// Parse private subnet IDs from comma-separated string
		privateSubnetIds := strings.Split(privateSubnetIdsStr, ",")

		// Validate required network data exists
		if vpcId == "" || len(privateSubnetIds) == 0 || privateSubnetIds[0] == "" || resourceId == "" {
			t.Fatal("❌ Cannot create database: Missing network data. Run network setup stage first.")
		}

		// read eks cluster security group IDs if available for both disk-enabled and disk-disabled clusters
		// create a list of EKS clusters with their security group IDs
		eksClusters := []map[string]interface{}{}
		_, err := os.Stat(suite.workingDir + "/eks-disk-enabled")
		if err != nil {
			t.Logf("❌ Error checking eks-disk-enabled output directory: %v",
				err)
		} else {
			// Load EKS disk-enabled cluster security group IDs
			eksSecurityGroupIdDiskEnabled := test_structure.LoadString(t, suite.workingDir+"/eks-disk-enabled", "cluster_security_group_id")
			nodeSecurityGroupIdDiskEnabled := test_structure.LoadString(t, suite.workingDir+"/eks-disk-enabled", "node_security_group_id")
			clusterNameDiskEnabled := test_structure.LoadString(t, suite.workingDir+"/eks-disk-enabled", "cluster_name")
			if eksSecurityGroupIdDiskEnabled != "" && nodeSecurityGroupIdDiskEnabled != "" {
				eksClusters = append(eksClusters, map[string]interface{}{
					"cluster_name":              clusterNameDiskEnabled,
					"cluster_security_group_id": eksSecurityGroupIdDiskEnabled,
					"node_security_group_id":    nodeSecurityGroupIdDiskEnabled,
				})
			}
			t.Logf("🔗 EKS cluster (disk-enabled) security group IDs loaded for database access")
		}

		_, err = os.Stat(suite.workingDir + "/eks-disk-disabled")
		if err != nil {
			t.Logf("❌ Error checking eks-disk-disabled output directory: %v",
				err)
		} else {
			eksSecurityGroupIdDiskDisabled := test_structure.LoadString(t, suite.workingDir+"/eks-disk-disabled", "cluster_security_group_id")
			nodeSecurityGroupIdDiskDisabled := test_structure.LoadString(t, suite.workingDir+"/eks-disk-disabled", "node_security_group_id")
			clusterNameDiskDisabled := test_structure.LoadString(t, suite.workingDir+"/eks-disk-disabled", "cluster_name")
			// Load EKS disk-disabled cluster security group IDs
			if eksSecurityGroupIdDiskDisabled != "" && nodeSecurityGroupIdDiskDisabled != "" {
				eksClusters = append(eksClusters, map[string]interface{}{
					"cluster_name":              clusterNameDiskDisabled,
					"cluster_security_group_id": eksSecurityGroupIdDiskDisabled,
					"node_security_group_id":    nodeSecurityGroupIdDiskDisabled,
				})
			}
			t.Logf("🔗 EKS cluster (disk-disabled) security group IDs loaded for database access")
		}

		if len(eksClusters) == 0 {
			t.Fatal("❌ Cannot create database: No EKS clusters found. Ensure at least one EKS cluster is created before the database stage.")
		}

		t.Logf("🔗 Using infrastructure family: %s", resourceId)

		// Set up database example
		databasePath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId, utils.DataBaseDir, utils.DataBaseDir)

		dbOptions := &terraform.Options{
			TerraformDir: databasePath,
			Vars: map[string]interface{}{
				"profile":                 awsProfile,
				"region":                  awsRegion,
				"name_prefix":             fmt.Sprintf("%s-db", resourceId),
				"vpc_id":                  vpcId,
				"database_subnet_ids":     privateSubnetIds,
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
				// Load EKS security group IDs if available (using disk-enabled cluster for database access)
				"eks_clusters": eksClusters,
				"tags": map[string]string{
					"Environment": "test",
					"Project":     "materialize",
					"TestRun":     resourceId,
				},
			},
			RetryableTerraformErrors: map[string]string{
				"RequestError": "Request failed",
			},
			MaxRetries:         TestMaxRetries,
			TimeBetweenRetries: TestRetryDelay,
			NoColor:            true,
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, suite.workingDir+"/database", dbOptions)

		// Apply
		terraform.InitAndApply(t, dbOptions)

		// Validate all database outputs
		databaseEndpoint := terraform.Output(t, dbOptions, "database_endpoint")
		databasePort := terraform.Output(t, dbOptions, "database_port")
		databaseName := terraform.Output(t, dbOptions, "database_name")
		databaseUsername := terraform.Output(t, dbOptions, "database_username")
		databaseIdentifier := terraform.Output(t, dbOptions, "database_identifier")

		// Comprehensive validation
		suite.NotEmpty(databaseEndpoint, "Database endpoint should not be empty")
		suite.Contains(databaseEndpoint, ".rds.amazonaws.com", "Database endpoint should be a valid RDS endpoint")
		suite.Equal("5432", databasePort, "Database port should be 5432")
		suite.Equal(TestDBName, databaseName, "Database name should match the configured value")
		suite.Equal(TestDBUsername, databaseUsername, "Database username should match the configured value")
		suite.Contains(databaseIdentifier, resourceId, "Database identifier should contain the resource ID")

		// Save database outputs for future stages
		test_structure.SaveString(t, suite.workingDir+"/database", "database_endpoint", databaseEndpoint)
		test_structure.SaveString(t, suite.workingDir+"/database", "database_port", databasePort)
		test_structure.SaveString(t, suite.workingDir+"/database", "database_name", databaseName)
		test_structure.SaveString(t, suite.workingDir+"/database", "database_identifier", databaseIdentifier)
		test_structure.SaveString(t, suite.workingDir+"/database", "database_username", databaseUsername)

		t.Logf("✅ Database created successfully:")
		t.Logf("  🔗 Endpoint: %s:%s", databaseEndpoint, databasePort)
		t.Logf("  📛 Database Name: %s", databaseName)
		t.Logf("  👤 Username: %s", databaseUsername)
		t.Logf("  🏷️ Identifier: %s", databaseIdentifier)

		// TODO add checks to ensure database is created and accessible
	})

	// Stage 5: Materialize Setup (Disk Enabled)
	test_structure.RunTestStage(t, "setup_materialize_disk_enabled", func() {
		// Ensure workingDir is set
		if suite.workingDir == "" {
			t.Fatal("❌ Cannot create Materialize: Working directory not set. Run network setup stage first.")
		}

		// Load saved EKS disk-enabled cluster data
		clusterName := test_structure.LoadString(t, suite.workingDir+"/eks-disk-enabled", "cluster_name")
		clusterEndpoint := test_structure.LoadString(t, suite.workingDir+"/eks-disk-enabled", "cluster_endpoint")
		clusterCertificateAuthorityData := test_structure.LoadString(t, suite.workingDir+"/eks-disk-enabled", "cluster_certificate_authority_data")
		oidcProviderArn := test_structure.LoadString(t, suite.workingDir+"/eks-disk-enabled", "oidc_provider_arn")
		clusterOidcIssuerUrl := terraform.Output(t, test_structure.LoadTerraformOptions(t, suite.workingDir+"/eks-disk-enabled"), "cluster_oidc_issuer_url")
		resourceId := test_structure.LoadString(t, suite.workingDir, "resource_unique_id")

		if clusterName == "" || clusterEndpoint == "" || oidcProviderArn == "" || clusterCertificateAuthorityData == "" || clusterOidcIssuerUrl == "" {
			t.Fatal("❌ Cannot create Materialize: Missing EKS disk-enabled cluster data. Run EKS setup stage first.")
		}

		// Load VPC ID and private subnet IDs
		vpcId := test_structure.LoadString(t, suite.workingDir, "vpc_id")
		privateSubnetIdsStr := test_structure.LoadString(t, suite.workingDir, "private_subnet_ids")
		privateSubnetIds := strings.Split(privateSubnetIdsStr, ",")
		if vpcId == "" || len(privateSubnetIds) == 0 {
			t.Fatal("❌ Cannot create Materialize: Missing VPC or private subnet IDs. Run network setup stage first.")
		}

		// Load database details
		databaseEndpoint := test_structure.LoadString(t, suite.workingDir+"/database", "database_endpoint")
		databaseName := test_structure.LoadString(t, suite.workingDir+"/database", "database_name")
		databaseUsername := test_structure.LoadString(t, suite.workingDir+"/database", "database_username")

		if databaseEndpoint == "" || databaseName == "" || databaseUsername == "" {
			t.Fatal("❌ Cannot create Materialize: Missing database details. Run database setup stage first.")
		}

		t.Logf("🔗 Using EKS disk-enabled cluster: %s", clusterName)

		// Set up Materialize example with disk enabled
		materializePath := helpers.SetupTestWorkspace(t, utils.AWS, resourceId, utils.MaterializeDir, utils.MaterializeDiskEnabledDir)
		expectedInstanceNamespace := "mz-disk-instance"
		expectedOperatorNamespace := "mz-disk-operator"
		expectedOpenEbsNamespace := "openebs-disk"

		materializeOptions := &terraform.Options{
			TerraformDir: materializePath,
			Vars: map[string]interface{}{
				"profile": awsProfile,
				"region":  awsRegion,
				// vpc and subnet details
				"vpc_id":     vpcId,
				"subnet_ids": privateSubnetIds,

				// Cluster details
				"cluster_name":                       clusterName,
				"cluster_endpoint":                   clusterEndpoint,
				"cluster_certificate_authority_data": clusterCertificateAuthorityData,
				"oidc_provider_arn":                  oidcProviderArn,
				"cluster_oidc_issuer_url":            clusterOidcIssuerUrl,

				// Open ebs details
				"openebs_namespace":     expectedOpenEbsNamespace,
				"openebs_chart_version": TestOpenEbsVersion,

				// S3 details
				"bucket_lifecycle_rules":   []interface{}{},
				"bucket_force_destroy":     true,
				"enable_bucket_versioning": false,
				"enable_bucket_encryption": false,

				// Cert Manager details
				"install_cert_manager":           true,
				"cert_manager_install_timeout":   600,
				"cert_manager_chart_version":     TestCertManagerVersion,
				"cert_manager_namespace":         "cert-manager-disk",
				"use_self_signed_cluster_issuer": true,

				// Database details
				"database_username": databaseUsername,
				"database_password": TestPassword,
				"database_endpoint": databaseEndpoint,
				"database_name":     databaseName,

				// Disk setup details
				"enable_disk_support": true,

				// Operator details
				"operator_namespace": expectedOperatorNamespace,
				// Materialize instance details
				"install_materialize_instance":      false,
				"instance_name":                     fmt.Sprintf("%s-de", resourceId),
				"name_prefix":                       fmt.Sprintf("%s-de", resourceId),
				"instance_namespace":                expectedInstanceNamespace,
				"external_login_password_mz_system": TestPassword,

				// NLB details
				// "create_nlb":                       true,
				"enable_cross_zone_load_balancing": true,

				// Tags
				"tags": map[string]string{
					"Environment": "test",
					"Project":     "materialize",
					"TestRun":     resourceId,
					"DiskEnabled": "true",
				},
			},
			RetryableTerraformErrors: map[string]string{
				"RequestError": "Request failed",
			},
			MaxRetries:         TestMaxRetries,
			TimeBetweenRetries: TestRetryDelay,
			NoColor:            true,
		}

		// Save terraform options for potential cleanup stage
		test_structure.SaveTerraformOptions(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), materializeOptions)

		// Apply
		terraform.InitAndApply(t, materializeOptions)

		t.Logf("✅ Phase 1: Materialize operator installed on disk-enabled cluster")

		// Phase 2: Update variables for instance deployment
		materializeOptions.Vars["install_materialize_instance"] = true

		// Phase 2: Apply with instance enabled
		terraform.Apply(t, materializeOptions)

		// Save Materialize outputs for subsequent stages
		s3BucketName := terraform.Output(t, materializeOptions, "s3_bucket_name")
		metadataBackendURL := terraform.Output(t, materializeOptions, "metadata_backend_url")
		persistBackendURL := terraform.Output(t, materializeOptions, "persist_backend_url")
		materializeS3RoleArn := terraform.Output(t, materializeOptions, "materialize_s3_role_arn")
		nlbDetails := terraform.OutputMap(t, materializeOptions, "nlb_details")
		nlbArn := nlbDetails["arn"]
		nlbDNSName := nlbDetails["dns_name"]
		instanceInstalled := terraform.Output(t, materializeOptions, "instance_installed")
		instanceResourceId := terraform.Output(t, materializeOptions, "instance_resource_id")
		clusterIssuerName := terraform.Output(t, materializeOptions, "cluster_issuer_name")
		openebsInstalled := terraform.Output(t, materializeOptions, "openebs_installed")
		openebsNamespace := terraform.Output(t, materializeOptions, "openebs_namespace")
		operatorNamespace := terraform.Output(t, materializeOptions, "operator_namespace")

		suite.Equal("true", instanceInstalled, "Materialize instance should be installed")
		suite.NotEmpty(instanceResourceId, "Materialize instance resource ID should not be empty")
		suite.NotEmpty(s3BucketName, "S3 bucket name should not be empty")
		suite.NotEmpty(metadataBackendURL, "Metadata backend URL should not be empty")
		suite.NotEmpty(persistBackendURL, "Persist backend URL should not be empty")
		suite.NotEmpty(materializeS3RoleArn, "Materialize S3 role ARN should not be empty")
		suite.NotEmpty(nlbArn, "NLB ARN should not be empty")
		suite.NotEmpty(nlbDNSName, "NLB DNS name should not	 be empty")
		suite.NotEmpty(clusterIssuerName, "Cluster issuer name should not be empty")
		suite.Equal("true", openebsInstalled, "OpenEBS should be installed")
		suite.Equalf(expectedOpenEbsNamespace, openebsNamespace, "OpenEBS namespace should be %s", expectedOpenEbsNamespace)
		suite.Equalf(expectedOperatorNamespace, operatorNamespace, "Operator namespace equal %s", expectedOperatorNamespace)

		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "s3_bucket_name", s3BucketName)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "metadata_backend_url", metadataBackendURL)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "persist_backend_url", persistBackendURL)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "materialize_s3_role_arn", materializeS3RoleArn)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "nlb_arn", nlbArn)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "nlb_dns_name", nlbDNSName)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "instance_resource_id", instanceResourceId)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "cluster_issuer_name", clusterIssuerName)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "openebs_installed", openebsInstalled)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "openebs_namespace", openebsNamespace)
		test_structure.SaveString(t, filepath.Join(suite.workingDir, utils.MaterializeDiskEnabledDir), "operator_namespace", operatorNamespace)

		t.Logf("✅ Phase 2: Materialize instance created successfully:")
		t.Logf("  🗄️ S3 Bucket: %s", s3BucketName)
		t.Logf("  🗄️ Metadata Backend URL: %s", metadataBackendURL)
		t.Logf("  🗄️ Persist Backend URL: %s", persistBackendURL)
		t.Logf("  🗄️ Materialize S3 Role ARN: %s", materializeS3RoleArn)
		t.Logf("  🗄️ NLB ARN: %s", nlbArn)
		t.Logf("  🗄️ NLB DNS Name: %s", nlbDNSName)
		t.Logf("  🗄️ Instance Resource ID: %s", instanceResourceId)
		t.Logf("  🗄️ Cluster Issuer Name: %s", clusterIssuerName)
		t.Logf("  🗄️ OpenEBS Installed: %s", openebsInstalled)
		t.Logf("  🗄️ OpenEBS Namespace: %s", openebsNamespace)
		t.Logf("  🗄️ Operator Namespace: %s", operatorNamespace)
		t.Logf("  🗄️ Instance Installed: %s", instanceInstalled)
	})
}

func (suite *StagedDeploymentTestSuite) useExistingNetwork() {
	t := suite.T()
	lastRunDir, err := dir.GetLastRunTestStageDir(TestRunsDir)
	if err != nil {
		t.Fatalf("Unable to use existing network %v", err)
	}
	// Use the full path returned by the helper
	suite.workingDir = lastRunDir
	latestDir := filepath.Base(lastRunDir)

	// Load vpc id using test_structure (handles .test-data path internally)
	vpcID := test_structure.LoadString(t, suite.workingDir, "vpc_id")
	if vpcID == "" {
		t.Fatalf("❌ Cannot skip network creation: VPC Id is empty in stage output directory %s", latestDir)
	}

	t.Logf("♻️ Skipping network creation, using existing: %s (ID: %s)", vpcID, latestDir)
}

// TestStagedDeploymentSuite runs the staged deployment test suite
func TestStagedDeploymentSuite(t *testing.T) {
	// Run the test suite
	suite.Run(t, new(StagedDeploymentTestSuite))
}
