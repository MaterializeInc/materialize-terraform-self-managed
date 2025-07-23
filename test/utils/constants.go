package utils

const (
	// Dirs Containing Example terraforms for different cloud
	// TODO: i don't feel right about hardcoding dir names in code,
	// this shouldn't be bad, since it's just tests, but renaming dirs would need a change
	// here as well. Could take these as env vars but might do it later if needed.
	AWS   = "aws"
	GCP   = "gcp"
	Azure = "azure"

	ExamplesDir   = "examples"
	NetworkingDir = "test-networking"
	DataBaseDir   = "test-database"
	MainTestDir   = "test"
)
