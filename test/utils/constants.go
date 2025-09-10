package utils

const (
	// Dirs Containing Example terraforms for different cloud
	// TODO: i don't feel right about hardcoding dir names in code,
	// this shouldn't be bad, since it's just tests, but renaming dirs would need a change
	// here as well. Could take these as env vars but might do it later if needed.
	AWS   = "aws"
	GCP   = "gcp"
	Azure = "azurem"

	DiskEnabledSuffix  = "-disk-enabled"
	DiskDisabledSuffix = "-disk-disabled"

	DiskEnabledShortSuffix  = "de"
	DiskDisabledShortSuffix = "dd"

	ExamplesDir                = "examples"
	NetworkingDir              = "test-networking"
	DataBaseDir                = "test-database"
	DatabaseDiskEnabledDir     = DataBaseDir + DiskEnabledSuffix
	DatabaseDiskDisabledDir    = DataBaseDir + DiskDisabledSuffix
	EKSDir                     = "test-eks"
	EKSDiskEnabledDir          = EKSDir + DiskEnabledSuffix
	EKSDiskDisabledDir         = EKSDir + DiskDisabledSuffix
	MaterializeDir             = "test-materialize"
	MaterializeDiskEnabledDir  = MaterializeDir + DiskEnabledSuffix
	MaterializeDiskDisabledDir = MaterializeDir + DiskDisabledSuffix
	MainTestDir                = "test"

	AKSDir             = "test-aks"
	AKSDiskEnabledDir  = AKSDir + DiskEnabledSuffix
	AKSDiskDisabledDir = AKSDir + DiskDisabledSuffix

	GKEDir             = "test-gke"
	GKEDiskEnabledDir  = GKEDir + DiskEnabledSuffix
	GKEDiskDisabledDir = GKEDir + DiskDisabledSuffix
)
