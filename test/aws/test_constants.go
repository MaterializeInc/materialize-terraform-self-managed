package test

// Test configuration constants to ensure consistent, reliable testing
// and avoid flakiness from random selections or regional variations

const (
	// EKS-specific instance types
	TestEKSDiskEnabledInstanceType  = "r7gd.2xlarge"
	TestEKSDiskDisabledInstanceType = "r7g.2xlarge"

	// Kubernetes version
	TestKubernetesVersion = "1.33"

	// RDS instance classes that are reliably available
	TestRDSInstanceClassSmall = "db.t3.micro" // 2 vCPU, 1 GB RAM

	// PostgreSQL version that's widely available
	TestPostgreSQLVersion = "15"

	// Storage sizes for testing (smaller to reduce costs)
	TestAllocatedStorageSmall = 20

	// Max allocated storage
	TestMaxAllocatedStorageSmall = 40

	// Network CIDR blocks that don't conflict
	TestVPCCIDR = "10.0.0.0/16"

	// Custom CIDR blocks for multi-AZ tests
	TestPrivateSubnetCIDRA = "10.0.1.0/24"
	TestPrivateSubnetCIDRB = "10.0.2.0/24"
	TestPublicSubnetCIDRA  = "10.0.101.0/24"
	TestPublicSubnetCIDRB  = "10.0.102.0/24"

	// Retry configuration
	TestMaxRetries = 1
	TestRetryDelay = 10 // seconds

	// Test environment variables
	TestPassword   = "test-password-123!"
	TestDBName     = "materialize_test"
	TestDBUsername = "materialize_test"

	// Maintenance and backup windows
	TestMaintenanceWindow     = "sun:05:00-sun:06:00"
	TestBackupWindow          = "04:00-05:00"
	TestBackupRetentionPeriod = 7

	TestCertManagerVersion = "v1.18.0"
)
