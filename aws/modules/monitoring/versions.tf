terraform {
  # The repo-wide floor, but this module cannot follow it back down: the module
  # source in main.tf pins a tag whose name contains a `/`, and Terraform
  # truncated the ref there until 1.10 (hashicorp/terraform#35552).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0, < 5.101.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5.0, < 2.18.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0, < 3.3.0"
    }
    # The TargetGroupBinding is a CRD the AWS Load Balancer Controller installs, so
    # it cannot be applied with `kubernetes_manifest` — that provider looks the
    # schema up at plan time and fails before the CRD exists. Same provider and
    # version the `nlb` module uses.
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
