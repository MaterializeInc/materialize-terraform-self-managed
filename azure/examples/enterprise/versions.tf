terraform {
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.75.0"
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
      version = "2.4.0"
    }
    # Declared so users can drop in a local okta.tf (gitignored) to automate
    # the Okta SAML app + assignments for the Polis SCIM/SAML e2e test. Not
    # used unless that file is present, in which case provider "okta" is
    # configured there.
    okta = {
      source  = "okta/okta"
      version = "~> 4.0"
    }
  }
}
