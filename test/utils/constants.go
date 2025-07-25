package utils

const (
	// Dirs Containing Example terraforms for different cloud
	// TODO: i don't feel right about hardcoding dir names in code,
	// this shouldn't be bad, since it's just tests, but renaming dirs would need a change
	// here as well. Could take these as env vars but might do it later if needed.
	AWS   = "aws"
	GCP   = "gcp"
	Azure = "azure"

	DiskEnabledSuffix  = "-disk-enabled"
	DiskDisabledSuffix = "-disk-disabled"

	ExamplesDir        = "examples"
	NetworkingDir      = "test-networking"
	DataBaseDir        = "test-database"
	EKSDir             = "test-eks"
	EKSDiskEnabledDir  = EKSDir + DiskEnabledSuffix
	EKSDiskDisabledDir = EKSDir + DiskDisabledSuffix
	MainTestDir        = "test"
)
