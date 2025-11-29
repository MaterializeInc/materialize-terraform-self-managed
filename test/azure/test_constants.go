package test

// Test configuration constants to ensure consistent, reliable testing
// and avoid flakiness from random selections or regional variations

const (
	// Default test region (can be overridden by TEST_REGION env var)
	// Using westus2 as it has good availability for most Azure services
	TestRegion = "westus2"

	// VM sizes that are reliably available in westus2
	TestVMSizeSmall  = "Standard_D2s_v3" // 2 vCPU, 8 GB RAM
	TestVMSizeMedium = "Standard_D4s_v3" // 4 vCPU, 16 GB RAM
	TestVMSizeMemory = "Standard_E4s_v3" // 4 vCPU, 32 GB RAM

	// AKS-specific VM sizes for disk-enabled setup
	TestAKSDiskEnabledVMSize = "Standard_E4pds_v6" // 4 vCPU, 32 GB RAM, local SSD

	// AKS-specific VM sizes for disk-disabled setup
	TestAKSDiskDisabledVMSize = "Standard_D4s_v3" // 4 vCPU, 16 GB RAM, no local SSD

	// Kubernetes version
	TestKubernetesVersion = "1.32" // Stable Kubernetes version

	// Database SKUs that are reliably available
	TestDBSKUSmall  = "GP_Standard_D2s_v3" // 2 vCPU, 8 GB RAM
	TestDBSKUMedium = "GP_Standard_D4s_v3" // 4 vCPU, 16 GB RAM

	// PostgreSQL version that's widely available
	TestPostgreSQLVersion = "15"

	// Storage sizes for testing (smaller to reduce costs)
	TestStorageSizeSmall  = 32768  // 32 GB
	TestStorageSizeMedium = 65536  // 64 GB
	TestStorageSizeLarge  = 131072 // 128 GB

	// Disk sizes for VMs (in GB)
	TestDiskSizeSmall  = 50
	TestDiskSizeMedium = 100
	TestDiskSizeLarge  = 150

	EnableAPIServerVNetIntegration = true
	// Network CIDR blocks that don't conflict
	TestVNetAddressSpace    = "10.100.0.0/16"
	TestAKSSubnetCIDR       = "10.100.0.0/20"
	TestPostgresSubnetCIDR  = "10.100.16.0/24"
	TestAPIServerSubnetCIDR = "10.100.32.0/27"
	TestServiceCIDR         = "10.101.0.0/16"

	// Test timeouts (in seconds)
	TestTimeoutShort  = 300  // 5 minutes
	TestTimeoutMedium = 1800 // 30 minutes
	TestTimeoutLong   = 3600 // 1 hour

	// Retry configuration
	TestMaxRetries  = 1
	TestRetryDelay  = 10 // seconds
	TestParallelism = 10

	// Test environment variables
	TestPassword   = "test-password-123!"
	TestDBName     = "materialize_test"
	TestDBUsername = "materialize_test"

	// Storage configuration
	TestStorageAccountTier         = "Premium"
	TestStorageReplicationType     = "LRS"
	TestStorageAccountKind         = "BlockBlobStorage"
	TestStorageContainerName       = "materialize"
	TestStorageContainerAccessType = "private"

	// Node pool configuration
	TestNodePoolMinNodes  = 1
	TestNodePoolMaxNodes  = 5
	TestNodePoolNodeCount = 2

	// Backup retention
	TestBackupRetentionDays = 7

	// Resource naming format for Azure compatibility
	// Format: t{YYMMDDHHMMSS}-{letter}{random3}{letter}
	TestResourceIDFormat = "t%s-%c%s%c"
	TestRandomIDLength   = 3

	// Materialize configuration
	TestOpenEbsVersion     = "4.2.0"
	TestCertManagerVersion = "v1.18.0"

	// Materialize instance defaults
	TestMaterializeInstanceName = "materialize-test"
)
