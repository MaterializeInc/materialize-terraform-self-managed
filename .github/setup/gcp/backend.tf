terraform {
  backend "s3" {
    bucket  = "materialize-terraform-self-managed-state"
    key     = "github-setup/oidc/gcp/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "materialize-admin" # Add your profile name here since backend block doesn't accept variables
  }
}