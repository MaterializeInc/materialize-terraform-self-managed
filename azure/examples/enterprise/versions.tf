terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.81.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    deepmerge = {
      source  = "isometry/deepmerge"
      version = "~> 1.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "2.4.1"
    }
    # Only used by an optional local okta.tf (gitignored) that automates the Okta
    # SAML app for Polis testing and configures this provider.
    okta = {
      source  = "okta/okta"
      version = "~> 4.0"
    }
  }
}
