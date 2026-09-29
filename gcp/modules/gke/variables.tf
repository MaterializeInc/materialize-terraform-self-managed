variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
  nullable    = false
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix to be used for resource names. Service account ids derived from it must fit GCP's 30-character limit, so at most 15 characters unless node_service_account_id and workload_identity_service_account_id are set."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(coalesce(var.node_service_account_id, "${var.prefix}-gke-sa")) <= 30 &&
      length(coalesce(var.workload_identity_service_account_id, "${var.prefix}-materialize-sa")) <= 30
    )
    error_message = "Service account ids derived from prefix exceed 30 characters. Use a prefix of at most 15 characters, or set node_service_account_id and workload_identity_service_account_id."
  }
}

variable "node_service_account_id" {
  description = "account_id of the GKE node service account. Defaults to \"<prefix>-gke-sa\". Changing it on an existing deployment recreates the service account."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.node_service_account_id == null || can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.node_service_account_id))
    error_message = "node_service_account_id must be 6-30 characters of lowercase letters, digits, and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "workload_identity_service_account_id" {
  description = "account_id of the Materialize workload identity service account. Defaults to \"<prefix>-materialize-sa\". Changing it on an existing deployment recreates the service account."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.workload_identity_service_account_id == null || can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.workload_identity_service_account_id))
    error_message = "workload_identity_service_account_id must be 6-30 characters of lowercase letters, digits, and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "grant_node_service_account_roles" {
  description = "Grant the node service account roles/container.defaultNodeServiceAccount (logging, monitoring, metadata) and roles/artifactregistry.reader. Disable if you manage these grants yourself."
  type        = bool
  default     = true
  nullable    = false
}

variable "network_name" {
  description = "The name of the VPC network"
  type        = string
  nullable    = false
}

variable "subnet_name" {
  description = "The name of the subnet"
  type        = string
  nullable    = false
}

variable "namespace" {
  description = "The namespace where the Materialize Operator will be installed"
  type        = string
  nullable    = false
}

variable "orchestratord_service_account_name" {
  description = "The name of the operator's Kubernetes service account bound to the workload identity service account. Must match the Materialize operator chart's serviceAccount.name value (the operator module leaves this at the chart default, \"orchestratord\")."
  type        = string
  default     = "orchestratord"
  nullable    = false
}

variable "networking_mode" {
  description = "The networking mode for the GKE cluster"
  type        = string
  default     = "VPC_NATIVE"
  validation {
    condition     = contains(["VPC_NATIVE", "ROUTES"], var.networking_mode)
    error_message = "Networking mode must be either VPC_NATIVE or ROUTES"
  }
}

variable "datapath_provider" {
  description = "The datapath provider (CNI) for the GKE cluster. ADVANCED_DATAPATH is GKE Dataplane V2 (eBPF-based, enforces Kubernetes NetworkPolicy natively). DATAPATH_PROVIDER_UNSPECIFIED and LEGACY_DATAPATH use the legacy GKE CNI, which silently ignores NetworkPolicy resources. GKE cannot change the datapath provider on an existing cluster: changing this forces the cluster to be rebuilt."
  type        = string
  default     = "ADVANCED_DATAPATH"
  nullable    = false
  validation {
    condition     = contains(["ADVANCED_DATAPATH", "LEGACY_DATAPATH", "DATAPATH_PROVIDER_UNSPECIFIED"], var.datapath_provider)
    error_message = "Datapath provider must be one of ADVANCED_DATAPATH, LEGACY_DATAPATH, or DATAPATH_PROVIDER_UNSPECIFIED"
  }
}

variable "cluster_secondary_range_name" {
  description = "The name of the secondary range to use for pods"
  type        = string
  default     = "pods"
  nullable    = false
}

variable "services_secondary_range_name" {
  description = "The name of the secondary range to use for services"
  type        = string
  default     = "services"
  nullable    = false
}

variable "release_channel" {
  description = "The release channel for the GKE cluster"
  type        = string
  default     = "REGULAR"
  validation {
    condition     = contains(["UNSPECIFIED", "RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "Release channel must be one of UNSPECIFIED, RAPID, REGULAR, STABLE, or EXTENDED"
  }
}

variable "horizontal_pod_autoscaling_disabled" {
  description = "Whether to disable horizontal pod autoscaling"
  type        = bool
  default     = false
  nullable    = false
}

variable "http_load_balancing_disabled" {
  description = "Whether to disable HTTP load balancing"
  type        = bool
  default     = false
  nullable    = false
}

variable "gce_persistent_disk_csi_driver_enabled" {
  description = "Whether to enable the GCE persistent disk CSI driver"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_node_local_dns" {
  description = "Whether to enable GKE's NodeLocal DNSCache addon, which runs a DNS cache on every node. This is the supported way to get node-local DNS on GKE: with Dataplane V2 a self-deployed node-local-dns cannot intercept kube-dns traffic (service IPs are rewritten in eBPF before iptables sees them). Note: NodeLocal DNSCache caches cluster records for up to 5s even when CoreDNS serves TTL-0 records, and toggling this on an existing cluster recreates all node pools."
  type        = bool
  default     = false
  nullable    = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# GCP manages this CIDR block when not provided as input
variable "master_ipv4_cidr_block" {
  description = "The IP range in CIDR notation to use for the hosted master network. This range must not overlap with any other ranges in use within the cluster's network."
  type        = string
  default     = null
  nullable    = true
}

# modify this to restrict public access to master endpoint from specific IP ranges
variable "k8s_apiserver_authorized_networks" {
  description = "List of CIDR blocks to allow access to the Kubernetes master endpoint. Each entry should have cidr_block and display_name. Defaults to 0.0.0.0/0 to allow access from anywhere."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "Authorized networks"
  }]
  nullable = false
}

variable "enable_upgrade_notifications" {
  description = "Publish GKE upgrade notifications to a Pub/Sub topic and let orchestratord's service account subscribe to them and read node pool state. Required for the operator module's enable_node_upgrade_rollout_trigger."
  type        = bool
  default     = true
  nullable    = false
}

variable "node_locations" {
  description = "List of zones where cluster nodes will be created. Must be zones within the cluster's region. When null (the default), GKE distributes nodes across available zones."
  type        = list(string)
  default     = null
  nullable    = true

  validation {
    condition     = var.node_locations == null ? true : length(var.node_locations) > 0
    error_message = "node_locations cannot be an empty list. Use null to let GKE choose zones."
  }

  validation {
    condition = var.node_locations == null ? true : alltrue([
      for zone in var.node_locations : can(regex("^[a-z][a-z0-9-]*[0-9]-[a-z]$", zone))
    ])
    error_message = "Each zone must be in the format region-zone (e.g., us-central1-a)."
  }
}
