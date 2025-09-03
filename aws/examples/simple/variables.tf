variable "aws_region" {
  description = "The AWS region where the resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "A prefix to add to all resource names."
  type        = string
  default     = "mz-demo"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance. Default is false as it requires the Kubernetes cluster to be created first."
  type        = bool
  default     = false
}

variable "create_nlb" {
  description = "Whether to create a Network Load Balancer for the Materialize instance"
  type        = bool
  default     = true
}

variable "enable_disk_support" {
  description = "Enable disk support for Materialize using OpenEBS and NVME disks. When enabled, this configures OpenEBS, runs the disk setup script, and creates appropriate storage classes."
  type        = bool
  default     = true
}

# Networking Module Configuration
variable "networking_config" {
  description = "Configuration for the networking module"
  type = object({
    vpc_cidr             = string
    availability_zones   = list(string)
    private_subnet_cidrs = list(string)
    public_subnet_cidrs  = list(string)
    single_nat_gateway   = optional(bool, true)
  })
  default = {
    vpc_cidr             = "10.0.0.0/16"
    availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
    private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
    public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
    single_nat_gateway   = true # Use single NAT gateway to reduce costs for this example
  }
}

# EKS Module Configuration
variable "eks_config" {
  description = "Configuration for the EKS module"
  type = object({
    cluster_version                          = optional(string, "1.32")
    cluster_enabled_log_types                = optional(list(string), ["api", "audit"])
    enable_cluster_creator_admin_permissions = optional(bool, true)
  })
  default = {
    cluster_version                          = "1.32"
    cluster_enabled_log_types                = ["api", "audit"]
    enable_cluster_creator_admin_permissions = true
  }
}

# EKS Node Group Module Configuration
variable "eks_node_group_config" {
  description = "Configuration for the EKS node group module"
  type = object({
    node_group_name_suffix = optional(string, "mz")
    labels                 = optional(map(string), {})
  })
  default = {
    node_group_name_suffix = "mz"
    labels                 = {}
  }
}

# AWS Load Balancer Controller Module Configuration
variable "aws_lbc_config" {
  description = "Configuration for the AWS Load Balancer Controller"
  type = object({
    namespace            = optional(string, "kube-system")
    service_account_name = optional(string, "aws-load-balancer-controller")
    iam_name             = optional(string, "albc")
  })
  default = {
    namespace            = "kube-system"
    service_account_name = "aws-load-balancer-controller"
    # Final IAM Name would be var.name_prefix + iam_name
    iam_name = "albc"
  }
}

# OpenEBS Module Configuration
variable "disk_support_config" {
  description = "Advanced configuration for disk support (only used when enable_disk_support = true)"
  type = object({
    install_openebs   = optional(bool, true)
    openebs_version   = optional(string, "4.2.0")
    openebs_namespace = optional(string, "openebs")
  })
  default = {
    install_openebs   = true
    openebs_version   = "4.2.0"
    openebs_namespace = "openebs"
  }
}

# Certificate Manager Module Configuration
variable "cert_manager_config" {
  description = "Configuration for cert-manager"
  type = object({
    install_cert_manager         = optional(bool, true)
    cert_manager_install_timeout = optional(number, 300)
    cert_manager_chart_version   = optional(string, "v1.18.0")
    cert_manager_namespace       = optional(string, "cert-manager")
  })
  default = {
    install_cert_manager         = true
    cert_manager_install_timeout = 300
    cert_manager_chart_version   = "v1.18.0"
    cert_manager_namespace       = "cert-manager"
  }
}

# Database Module Configuration
variable "database_config" {
  description = "Configuration for the RDS PostgreSQL database"
  type = object({
    postgres_version      = optional(string, "15")
    instance_class        = optional(string, "db.t3.large")
    allocated_storage     = optional(number, 50)
    max_allocated_storage = optional(number, 100)
    database_name         = optional(string, "materialize")
    database_username     = optional(string, "materialize")
    multi_az              = optional(bool, false)
  })
  default = {
    postgres_version      = "15"
    instance_class        = "db.t3.large"
    allocated_storage     = 50
    max_allocated_storage = 100
    database_name         = "materialize"
    database_username     = "materialize"
    multi_az              = false
  }
}

# Storage Module Configuration
variable "storage_config" {
  description = "Configuration for S3 bucket"
  type = object({
    bucket_lifecycle_rules   = optional(list(any), [])
    bucket_force_destroy     = optional(bool, true)
    enable_bucket_versioning = optional(bool, false)
    enable_bucket_encryption = optional(bool, false)
  })
  default = {
    bucket_lifecycle_rules = []
    bucket_force_destroy   = true
    # For testing purposes, we are disabling encryption and versioning to allow for easier cleanup
    # This should be enabled in production environments for security and data integrity
    enable_bucket_versioning = false
    enable_bucket_encryption = false
  }
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

# NLB Module Configuration
variable "nlb_config" {
  description = "Configuration for the Network Load Balancer"
  type = object({
    enable_cross_zone_load_balancing = optional(bool, true)
  })
  default = {
    enable_cross_zone_load_balancing = true
  }
}
