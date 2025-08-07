package test

// Test configuration constants to ensure consistent, reliable testing
// and avoid flakiness from random selections or regional variations

const (
	// Fixed test region to avoid quota/availability issues with random regions
	// Using us-central1 to match the real terraform.tfvars example
	TestRegion = "us-central1"

	// Machine types that are reliably available in us-central1
	TestMachineTypeSmall  = "n2-standard-2" // 2 vCPU, 8 GB RAM
	TestMachineTypeMedium = "n2-standard-4" // 4 vCPU, 16 GB RAM
	TestMachineTypeMemory = "n2-highmem-2"  // 2 vCPU, 16 GB RAM

	// GKE-specific machine types
	TestGKEMachineType            = "n2-standard-2" // Standard GKE node type
	TestAlternativeGKEMachineType = "n2-standard-4" // Alternative GKE node type

	// Kubernetes version
	TestKubernetesVersion = "1.32" // Stable Kubernetes version

	// Database tiers that are reliably available
	TestDBTierSmall  = "db-custom-1-4096" // 1 vCPU, 4 GB RAM
	TestDBTierMedium = "db-custom-2-8192" // 2 vCPU, 8 GB RAM

	// PostgreSQL version that's widely available
	TestPostgreSQLVersion = "POSTGRES_15"

	// Disk sizes for testing (smaller to reduce costs)
	TestDiskSizeSmall  = 50
	TestDiskSizeMedium = 100
	TestDiskSizeLarge  = 150

	// Network CIDR blocks that don't conflict
	TestSubnetCIDR   = "10.100.0.0/20" // Different from default to avoid conflicts
	TestPodsCIDR     = "10.104.0.0/14"
	TestServicesCIDR = "10.108.0.0/20"

	// Custom CIDR blocks for custom tests (using RFC 1918 private ranges)
	TestCustomSubnetCIDR   = "10.200.0.0/20" // Changed from 192.168.100.0/20 to avoid conflicts
	TestCustomPodsCIDR     = "172.16.0.0/14"
	TestCustomServicesCIDR = "172.20.0.0/20"

	// Test timeouts (in seconds)
	TestTimeoutShort  = 300  // 5 minutes
	TestTimeoutMedium = 1800 // 30 minutes
	TestTimeoutLong   = 3600 // 1 hour

	// Retry configuration
	TestMaxRetries  = 1
	TestRetryDelay  = 10 // seconds
	TestParallelism = 10

	// TestRuns directory, this will be created in the directory where the tests are run
	TestRunsDir = "./testRuns"

	// Test environment variables
	TestPassword     = "test-password-123!"
	TestDBNameDisk   = "materialize-test-disk"
	TestDBNameNoDisk = "materialize-test-nodisk"
	TestDBUsername1  = "materialize-test-user1"
	TestDBUsername2  = "materialize-test-user2"
)
