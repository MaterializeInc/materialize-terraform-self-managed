terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0, < 6.57.0"
    }
  }
}

provider "aws" {
  profile = var.profile
  region  = "us-east-1"
}
