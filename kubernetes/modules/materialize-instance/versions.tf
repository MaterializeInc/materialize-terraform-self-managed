terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0"
    }
    kubectl = {
      source = "alekc/kubectl"
      # TODO: Unpin once fixed: https://github.com/alekc/terraform-provider-kubectl/issues/283
      version = ">= 2.2.0, < 2.3"
    }
  }
}
