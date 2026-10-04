terraform {
  # Cannot go lower even if the repo floor does: main.tf pins a module tag
  # containing `/`, which Terraform truncated before 1.10 (hashicorp/terraform#35552).
  required_version = ">= 1.10"

  required_providers {
    # Above the repo-wide `~> 6.0`: `bucket_namespace` on `aws_s3_bucket` shipped
    # in 6.37.0.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.37"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5.0, < 2.18.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0, < 2.39.0"
    }
    # For the TargetGroupBinding CRD, which `kubernetes_manifest` cannot plan
    # before the CRD exists. Same version as the `nlb` module.
    kubectl = {
      source  = "alekc/kubectl"
      version = "2.4.1"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0, < 3.10.0"
    }
  }
}
