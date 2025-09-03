variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  default     = "materialize"
}

variable "materialize_operator_namespace" {
  description = "Kubernetes namespace for Materialize Operator"
  type        = string
  default     = "materialize"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance. Default is false as it requires the Kubernetes cluster to be created first."
  type        = bool
  default     = false
}

variable "enable_disk_support" {
  description = "Enable disk support for Materialize using OpenEBS and local SSDs. When enabled, this configures OpenEBS, runs the disk setup script, and creates appropriate storage classes."
  type        = bool
  default     = true
}

# Networking Module Configuration
variable "network_config" {
  description = "Network configuration for the GKE cluster"
  type = object({
    subnets = list(object({
      name           = string
      cidr           = string
      region         = string
      private_access = optional(bool, true)
      secondary_ranges = optional(list(object({
        range_name    = string
        ip_cidr_range = string
      })), [])
    }))
  })
  default = {
    subnets = [
      {
        name           = "mz-subnet"
        cidr           = "10.0.0.0/20"
        region         = "us-central1"
        private_access = true
        secondary_ranges = [
          {
            range_name    = "pods"
            ip_cidr_range = "10.48.0.0/14"
          },
          {
            range_name    = "services"
            ip_cidr_range = "10.52.0.0/20"
          }
        ]
      }
    ]
  }
}

# GKE Module Configuration
variable "gke_nodepool_config" {
  description = "GKE cluster configuration. Make sure to use large enough machine types for your Materialize instances."
  type = object({
    node_count           = optional(number, 1)
    machine_type         = optional(string, "n2-highmem-8")
    disk_size_gb         = optional(number, 100)
    min_nodes            = optional(number, 1)
    max_nodes            = optional(number, 5)
    enable_private_nodes = optional(bool, true)
  })
  default = {
    node_count           = 1
    machine_type         = "n2-highmem-8"
    disk_size_gb         = 100
    min_nodes            = 1
    max_nodes            = 5
    enable_private_nodes = true
  }
}

# Database Module Configuration
variable "database_config" {
  description = "Cloud SQL configuration"
  type = object({
    tier    = optional(string, "db-custom-2-4096")
    version = optional(string, "POSTGRES_15")
    database = optional(object({
      name      = string
      charset   = optional(string, "UTF8")
      collation = optional(string, "en_US.UTF8")
    }), { name = "materialize" })
    user_name = optional(string, "materialize")
  })
  default = {
    tier      = "db-custom-2-4096"
    version   = "POSTGRES_15"
    database  = { name = "materialize" }
    user_name = "materialize"
  }
}

# Storage Module Configuration
variable "storage_config" {
  description = "Storage bucket configuration"
  type = object({
    storage_bucket_versioning  = optional(bool, false)
    storage_bucket_version_ttl = optional(number, 7)
  })
  default = {
    storage_bucket_versioning  = false
    storage_bucket_version_ttl = 7
  }
}

# Certificate Manager Module Configuration
variable "cert_manager_config" {
  description = "Certificate manager configuration"
  type = object({
    install_cert_manager         = optional(bool, true)
    cert_manager_namespace       = optional(string, "cert-manager")
    cert_manager_install_timeout = optional(number, 300)
    cert_manager_chart_version   = optional(string, "v1.17.1")
  })
  default = {
    install_cert_manager         = true
    cert_manager_namespace       = "cert-manager"
    cert_manager_install_timeout = 300
    cert_manager_chart_version   = "v1.18.0"
  }
}

# OpenEBS Module Configuration
variable "disk_support_config" {
  description = "Advanced configuration for disk support (only used when enable_disk_support = true)"
  type = object({
    install_openebs          = optional(bool, true)
    local_ssd_count          = optional(number, 1)
    openebs_version          = optional(string, "4.2.0")
    create_openebs_namespace = optional(bool, true)
    openebs_namespace        = optional(string, "openebs")
  })
  default = {
    install_openebs          = true
    local_ssd_count          = 1
    openebs_version          = "4.2.0"
    create_openebs_namespace = true
    openebs_namespace        = "openebs"
  }
}

variable "disk_setup_image" {
  description = "Docker image for the disk setup script"
  type        = string
  default     = "materialize/ephemeral-storage-setup-image:v0.1.1"
}

# Materialize Instance Module Configuration
variable "materialize_instance_config" {
  description = "Configuration for the Materialize instance"
  type = object({
    instance_name      = optional(string, "main")
    instance_namespace = optional(string, "materialize-environment")
  })
  default = {
    instance_name      = "main"
    instance_namespace = "materialize-environment"
  }
}
