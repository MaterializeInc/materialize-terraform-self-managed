variable "prefix" {
  description = "Prefix for the storage account and identity names this module creates."
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "Resource group holding the storage account and identities."
  type        = string
  nullable    = false
}

variable "location" {
  description = "Azure region for the storage account and identities."
  type        = string
  nullable    = false
}

variable "tenant_id" {
  description = "Entra tenant ID. Null reads it from the provider's own credentials, which is right unless the identities live in a different tenant than the one Terraform authenticated to."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace the monitoring stack is installed into. Also the namespace half of every federated-credential subject."
  type        = string
  default     = "monitoring"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether the monitoring module creates the namespace. False by default because the operator module already creates `monitoring`."
  type        = bool
  default     = false
  nullable    = false
}

# ==============================================================================
# Cluster identity
# ==============================================================================

variable "oidc_issuer_url" {
  description = "The AKS cluster's OIDC issuer URL, from the `aks` module. Requires `oidc_issuer_enabled` and `workload_identity_enabled` on the cluster."
  type        = string
  nullable    = false
}

# ==============================================================================
# Storage
# ==============================================================================

variable "loki_container_name" {
  description = "Blob container for Loki chunks and rules."
  type        = string
  default     = "mzmon-loki"
  nullable    = false
}

variable "thanos_container_name" {
  description = "Blob container for Thanos blocks."
  type        = string
  default     = "mzmon-thanos"
  nullable    = false
}

variable "account_replication_type" {
  description = "Replication for the telemetry storage account. LRS is the default because both backends treat object storage as replaceable — Loki re-ingests and Thanos re-uploads — so paying for ZRS buys less here than for the Materialize persist account."
  type        = string
  default     = "LRS"
  nullable    = false
}

variable "subnets" {
  description = "Subnet IDs allowed to reach the storage account. Empty leaves the account open to the configured default action, which is what a cluster without service endpoints needs."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "network_rules_default_action" {
  description = "Default action for the storage account's network rules when `subnets` is set."
  type        = string
  default     = "Deny"
  nullable    = false
}

variable "tags" {
  description = "Tags applied to the resources this module creates."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ==============================================================================
# Passed through to the monitoring module
# ==============================================================================

variable "chart_version" {
  description = "Override the materialize-monitoring chart version. Leave null to use the version the pinned module ships with — the two are one release."
  type        = string
  default     = null
}

variable "sizing" {
  description = "Deployment size: small, medium, or large. The chart's defaults are medium."
  type        = string
  default     = "medium"
  nullable    = false
}

variable "materialize_instance_namespace" {
  description = "Namespace the Materialize instance runs in."
  type        = string
  default     = "materialize-environment"
  nullable    = false
}

variable "materialize_operator_namespace" {
  description = "Namespace the Materialize operator runs in."
  type        = string
  default     = "materialize"
  nullable    = false
}

variable "install_metrics_server" {
  description = "Install metrics-server as part of the monitoring stack. Set true when the operator module has `install_metrics_server = false`, or the Materialize Console loses cluster metrics."
  type        = bool
  default     = false
  nullable    = false
}

variable "node_selector" {
  description = "Node selector for the centralized monitoring workloads. Not applied to the Alloy agent DaemonSet, which must reach every node."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "storage_class" {
  description = "StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos receive/compactor/store-gateway). Null uses the cluster default; AKS ships `managed-csi`."
  type        = string
  default     = null
}

variable "tolerations" {
  description = "Tolerations for the monitoring workloads, including the Alloy agent DaemonSet."
  type = list(object({
    key      = optional(string)
    operator = optional(string, "Equal")
    value    = optional(string)
    effect   = optional(string)
  }))
  default  = []
  nullable = false
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Generated when null."
  type        = string
  default     = null
  sensitive   = true
}

variable "additional_values" {
  description = "Raw YAML documents appended to the Helm values, last, so they override everything the modules compute."
  type        = list(string)
  default     = []
  nullable    = false
}
