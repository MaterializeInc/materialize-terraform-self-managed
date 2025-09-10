variable "subscription_id" {
  description = "The ID of the Azure subscription"
  type        = string
}

variable "location" {
  description = "The location of the Azure subscription"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "cluster_identity_principal_id" {
  description = "The principal ID of the cluster identity"
  type        = string
}

variable "subnets" {
  description = "The subnets that should be able to access the storage account"
  type        = list(string)
}

variable "prefix" {
  description = "The prefix for resource naming"
  type        = string
}

variable "cluster_endpoint" {
  description = "The endpoint of the AKS cluster"
  type        = string
}

variable "kube_config" {
  description = "The kube config of the AKS cluster"
  type = object({
    client_certificate     = string
    client_key             = string
    cluster_ca_certificate = string
  })
  sensitive = true
}

variable "database_host" {
  description = "The hostname of the database server"
  type        = string
}

variable "database_name" {
  description = "The name of the database"
  type        = string
}

variable "database_admin_user" {
  description = "The database user credentials"
  type = object({
    name     = string
    password = string
  })
  sensitive = true
}

variable "storage_config" {
  description = "Storage configuration"
  type = object({
    container_name        = string
    container_access_type = string
  })
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

variable "install_cert_manager" {
  description = "Whether to install cert-manager"
  type        = bool
}

variable "cert_manager_namespace" {
  description = "The namespace for cert-manager"
  type        = string
}

variable "cert_manager_install_timeout" {
  description = "Timeout for installing cert-manager"
  type        = number
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager helm chart"
  type        = string
}

variable "enable_disk_support" {
  description = "Whether to install OpenEBS"
  type        = bool
}

variable "openebs_namespace" {
  description = "The namespace for OpenEBS"
  type        = string
}

variable "openebs_version" {
  description = "The version of OpenEBS"
  type        = string
}

variable "operator_namespace" {
  description = "The namespace for the Materialize operator"
  type        = string
}

variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance"
  type        = bool
}

variable "instance_name" {
  description = "The name of the Materialize instance"
  type        = string
}

variable "instance_namespace" {
  description = "The namespace of the Materialize instance"
  type        = string
}
