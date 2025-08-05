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

variable "gke_config" {
  description = "GKE cluster configuration. Make sure to use large enough machine types for your Materialize instances."
  type = object({
    node_count   = number
    machine_type = string
    disk_size_gb = number
    min_nodes    = number
    max_nodes    = number
  })
  default = {
    node_count   = 1
    machine_type = "n2-highmem-8"
    disk_size_gb = 100
    min_nodes    = 1
    max_nodes    = 5
  }
}

variable "database_config" {
  description = "Cloud SQL configuration"
  type = object({
    tier     = optional(string, "db-custom-2-4096")
    version  = optional(string, "POSTGRES_15")
    username = optional(string, "materialize")
    db_name  = optional(string, "materialize")
  })

  default = {
    tier     = "db-custom-2-4096"
    version  = "POSTGRES_15"
    username = "materialize"
    db_name  = "materialize"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for Materialize"
  type        = string
  default     = "materialize"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# Materialize Helm Chart Variables
variable "install_materialize_operator" {
  description = "Whether to install the Materialize operator"
  type        = bool
  default     = true
}

variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance. Default is false as it requires the Kubernetes cluster to be created first."
  type        = bool
  default     = false
}

variable "storage_bucket_versioning" {
  description = "Enable bucket versioning. This should be enabled for production deployments."
  type        = bool
  default     = false
}

variable "storage_bucket_version_ttl" {
  description = "Sets the TTL (in days) on non current storage bucket objects. This must be set if storage_bucket_versioning is turned on."
  type        = number
  default     = 7
}

variable "install_cert_manager" {
  description = "Whether to install cert-manager."
  type        = bool
  default     = true
}

variable "cert_manager_namespace" {
  description = "The name of the namespace in which cert-manager is or will be installed."
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_install_timeout" {
  description = "Timeout for installing the cert-manager helm chart, in seconds."
  type        = number
  default     = 300
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager helm chart to install."
  type        = string
  default     = "v1.17.1"
}

# Disk support configuration
variable "enable_disk_support" {
  description = "Enable disk support for Materialize using OpenEBS and local SSDs. When enabled, this configures OpenEBS, runs the disk setup script, and creates appropriate storage classes."
  type        = bool
  default     = true
}

variable "disk_support_config" {
  description = "Advanced configuration for disk support (only used when enable_disk_support = true)"
  type = object({
    install_openebs   = optional(bool, true)
    local_ssd_count   = optional(number, 1)
    openebs_version   = optional(string, "4.2.0")
    openebs_namespace = optional(string, "openebs")
  })
  default = {}
}

variable "disk_setup_image" {
  description = "Docker image for the disk setup script"
  type        = string
  default     = "materialize/ephemeral-storage-setup-image:v0.1.1"
}
