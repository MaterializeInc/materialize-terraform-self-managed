package test

// Test configuration constants to ensure consistent, reliable testing
// and avoid flakiness from random selections or regional variations

const (
	// Fixed test region to avoid quota/availability issues with random regions
	// Using us-west-2 for reliable availability and quota
	TestRegion = "us-west-2"

	// Availability zones in us-west-2
	TestAvailabilityZoneA = "us-west-2a"
	TestAvailabilityZoneB = "us-west-2b"
	TestAvailabilityZoneC = "us-west-2c"

	// EC2 instance types that are reliably available in us-west-2
	TestInstanceTypeSmall  = "t3.medium" // 2 vCPU, 4 GB RAM
	TestInstanceTypeMedium = "t3.large"  // 2 vCPU, 8 GB RAM
	TestInstanceTypeLarge  = "t3.xlarge" // 4 vCPU, 16 GB RAM

	// EKS-specific instance types
	TestEKSDiskEnabledInstanceType  = "r7gd.2xlarge"
	TestEKSDiskDisabledInstanceType = "r7g.2xlarge"

	// Kubernetes version
	TestKubernetesVersion = "1.32"

	// RDS instance classes that are reliably available
	TestRDSInstanceClassSmall  = "db.t3.micro"  // 2 vCPU, 1 GB RAM
	TestRDSInstanceClassMedium = "db.t3.small"  // 2 vCPU, 2 GB RAM
	TestRDSInstanceClassLarge  = "db.t3.medium" // 2 vCPU, 4 GB RAM

	// PostgreSQL version that's widely available
	TestPostgreSQLVersion = "15"

	// Storage sizes for testing (smaller to reduce costs)
	TestAllocatedStorageSmall  = 20
	TestAllocatedStorageMedium = 50
	TestAllocatedStorageLarge  = 100

	// Max allocated storage
	TestMaxAllocatedStorageSmall  = 40
	TestMaxAllocatedStorageMedium = 100
	TestMaxAllocatedStorageLarge  = 200

	// Network CIDR blocks that don't conflict
	TestVPCCIDR           = "10.0.0.0/16"
	TestPrivateSubnetCIDR = "10.0.1.0/24"
	TestPublicSubnetCIDR  = "10.0.101.0/24"

	// Custom CIDR blocks for multi-AZ tests
	TestPrivateSubnetCIDRA = "10.0.1.0/24"
	TestPrivateSubnetCIDRB = "10.0.2.0/24"
	TestPublicSubnetCIDRA  = "10.0.101.0/24"
	TestPublicSubnetCIDRB  = "10.0.102.0/24"

	// Test timeouts (in seconds)
	TestTimeoutShort  = 300  // 5 minutes
	TestTimeoutMedium = 1800 // 30 minutes
	TestTimeoutLong   = 3600 // 1 hour

	// Retry configuration
	TestMaxRetries  = 1
	TestRetryDelay  = 10 // seconds
	TestParallelism = 10

	// TestRuns directory, this will be created in the directory where the tests are run

	// Test environment variables
	TestPassword   = "test-password-123!"
	TestDBName     = "materialize_test"
	TestDBUsername = "materialize_test"

	// Maintenance and backup windows
	TestMaintenanceWindow     = "sun:05:00-sun:06:00"
	TestBackupWindow          = "04:00-05:00"
	TestBackupRetentionPeriod = 7

	// Resource naming format for AWS compatibility
	// Format: t{YYMMDDHHMMSS}-{random5}
	TestResourceIDFormat = "t%s-%s"
	TestRandomIDLength   = 5

	TestOpenEbsVersion     = "4.2.0"
	TestCertManagerVersion = "v1.18.0"
)
