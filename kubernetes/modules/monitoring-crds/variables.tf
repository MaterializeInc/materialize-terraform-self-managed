variable "namespace" {
  description = "Namespace for the monitoring stack. Holds the CRDs release's metadata, and is where the monitoring module installs everything else."
  type        = string
  default     = "monitoring"
  nullable    = false
}

variable "create_namespace" {
  description = "Create the namespace. Set false when something else already creates it before this module runs."
  type        = bool
  default     = true
  nullable    = false
}

variable "install_crds" {
  description = <<-EOT
    Install the materialize-monitoring-crds chart (prometheus-operator and grafana-operator CRDs).

    Set false when the monitoring stack is not installed, or when the cluster already has these
    CRDs from elsewhere, such as kube-prometheus-stack or a platform team that owns CRDs centrally;
    Helm cannot install objects another release owns. Charts that ship ServiceMonitors then have to
    wait for whoever does install them.

    The CRDs carry `helm.sh/resource-policy: keep`, so turning this off uninstalls the release but
    leaves the CRDs, and every resource that uses them, in place.
  EOT
  type        = bool
  default     = true
  nullable    = false
}

variable "chart_registry" {
  description = "OCI registry holding the materialize-monitoring charts. Override for a mirrored or air-gapped registry. Keep it in step with the monitoring module's."
  type        = string
  default     = "oci://ghcr.io/materializeinc/helm-charts"
  nullable    = false
}

variable "chart_version" {
  description = "Version of the materialize-monitoring-crds chart. It is versioned separately from the monitoring chart."
  type        = string
  # renovate: datasource=docker depName=materializeinc/helm-charts/materialize-monitoring-crds registryUrl=https://ghcr.io
  default  = "0.3.0"
  nullable = false
}
