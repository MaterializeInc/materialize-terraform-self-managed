package utils

const (
	// Project name used in tags/labels across all cloud providers
	ProjectName = "materialize-terraform"

	// Dirs Containing Example terraforms for different cloud
	// TODO: i don't feel right about hardcoding dir names in code,
	// this shouldn't be bad, since it's just tests, but renaming dirs would need a change
	// here as well. Could take these as env vars but might do it later if needed.
	AWS   = "aws"
	GCP   = "gcp"
	Azure = "azurem"

	// Test infrastructure directories
	MainTestDir = "test"
	FixturesDir = "fixtures"

	// Disk configuration suffixes
	DiskEnabledSuffix  = "-disk-enabled"
	DiskDisabledSuffix = "-disk-disabled"

	DiskEnabledShortSuffix  = "de"
	DiskDisabledShortSuffix = "dd"

	// Fixture names (source directories in test/{cloud}/fixtures/)
	NetworkingFixture  = "networking"
	DatabaseFixture    = "database"
	EKSFixture         = "eks"
	AKSFixture         = "aks"
	GKEFixture         = "gke"
	MaterializeFixture = "materialize"

	// Runtime directory names (destinations in test/{cloud}/{uniqueId}/)
	NetworkingDir              = "networking"
	DataBaseDir                = "database"
	DatabaseDiskEnabledDir     = DataBaseDir + DiskEnabledSuffix
	DatabaseDiskDisabledDir    = DataBaseDir + DiskDisabledSuffix
	EKSDir                     = "eks"
	EKSDiskEnabledDir          = EKSDir + DiskEnabledSuffix
	EKSDiskDisabledDir         = EKSDir + DiskDisabledSuffix
	MaterializeDir             = "materialize"
	MaterializeDiskEnabledDir  = MaterializeDir + DiskEnabledSuffix
	MaterializeDiskDisabledDir = MaterializeDir + DiskDisabledSuffix

	AKSDir             = "aks"
	AKSDiskEnabledDir  = AKSDir + DiskEnabledSuffix
	AKSDiskDisabledDir = AKSDir + DiskDisabledSuffix

	GKEDir             = "gke"
	GKEDiskEnabledDir  = GKEDir + DiskEnabledSuffix
	GKEDiskDisabledDir = GKEDir + DiskDisabledSuffix
)
