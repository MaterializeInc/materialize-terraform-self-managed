variable "prefix" {
  description = "Prefix for the storage account and identity names this module creates. Hyphens are stripped for the storage account name, and what remains is capped at 13 characters: the account name is limited to 24, of which `mzmon` and the 6-character uniqueness suffix take 11."
  type        = string
  nullable    = false

  # The suffix is the only thing making this name globally unique, so it is the
  # one part that must never be truncated. Past 13 stripped characters a
  # `substr` to 24 starts eating it, and past 19 none of it survives — at which
  # point two deployments sharing a prefix collide on a name that has to be
  # unique across all of Azure.
  validation {
    condition     = length(replace(var.prefix, "-", "")) <= 13
    error_message = "prefix must be at most 13 characters once hyphens are removed; the storage account name is capped at 24 and `mzmon` plus the uniqueness suffix uses 11."
  }
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

variable "chart_registry" {
  description = "OCI registry holding the materialize-monitoring charts. Override for a mirrored or air-gapped registry; there is no way to reach this through `additional_values`."
  type        = string
  default     = null
}

variable "enable_monitoring_crds" {
  description = "Install the materialize-monitoring-crds chart (prometheus-operator and grafana-operator CRDs). Set false when the cluster already has them from elsewhere, such as kube-prometheus-stack or a platform team that owns CRDs centrally. Null uses the monitoring module's default."
  type        = bool
  default     = null
}

variable "install_timeout" {
  description = "Timeout for each Helm release, in seconds. Null uses the monitoring module's default, which is well above Helm's 300s because a first install brings up Loki, Thanos, Grafana, and both Alloy roles together."
  type        = number
  default     = null
}

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

variable "min_zones" {
  description = <<-EOT
    Number of availability zones the node pool can actually launch in, used to adjust the hard zone
    spread the chart puts on Thanos Receive and Loki's ingesters. Null leaves the chart's defaults
    alone, which assume two or more zones.

    Set it when that assumption does not hold, because the constraints fail closed rather than
    degrading: `0` for a cluster whose nodes carry no `topology.kubernetes.io/zone` label, or the
    real zone count otherwise. On AKS this is the one to check — an AKS node pool created without
    `zones` is not zone-labelled, and a single zone leaves those pods **Pending forever** rather
    than merely unbalanced.
  EOT
  type        = number
  default     = null
}

# ==============================================================================
# Extra metrics destinations
# ==============================================================================
# Passed straight through to the monitoring module rather than flattened the way
# `enable_google_cloud_metrics` is. That one is flat because it provisions cloud
# resources — a service account and its Workload Identity binding — so this
# module needs a plan-known toggle to gate them. Datadog and OTLP provision
# nothing, so a flat mirror here would only be a second place for the defaults
# and the validation to drift from.

variable "datadog_metrics" {
  description = <<-EOT
    Also export metrics to Datadog from the Alloy gateway. Null disables it; Thanos is unaffected.
    Requires `datadog_api_key`.

    `min_importance` is the cost lever — Datadog bills per custom metric, so it defaults to
    `essential` rather than the `recommended` the other destinations use.
  EOT
  type = object({
    site            = optional(string, "datadoghq.com")
    min_importance  = optional(string, "essential")
    metric_endpoint = optional(string)
    logs_endpoint   = optional(string)
  })
  default = null
}

variable "datadog_api_key" {
  description = "Datadog API key for `datadog_metrics`. Reaches the gateway as a Secret the monitoring module creates, never through the Helm values."
  type        = string
  default     = null
  sensitive   = true
}

variable "otlp_metrics" {
  description = <<-EOT
    Also export metrics to a generic OTLP endpoint from the Alloy gateway — Honeycomb, Grafana
    Cloud, or your own collector. Null disables it; Thanos is unaffected.

    `url` is a `host[:port]` with no scheme. `auth_headers` carries **non-secret** headers only
    (a dataset or tenant name); credentials belong in `otlp_auth_header_secrets`.
  EOT
  type = object({
    url            = string
    protocol       = optional(string, "grpc")
    compression    = optional(string)
    min_importance = optional(string, "recommended")
    auth_headers   = optional(map(string), {})
  })
  default = null
}

variable "otlp_auth_header_secrets" {
  description = "Secret request headers for `otlp_metrics`, as header name to value — Honeycomb's `x-honeycomb-team`, for instance. Each reaches the gateway as a Secret the monitoring module creates. Cannot be combined with `otlp_auth_bearer_token`."
  type        = map(string)
  default     = {}
  nullable    = false
  sensitive   = true
}

variable "otlp_auth_bearer_token" {
  description = "Bearer token for `otlp_metrics`, for endpoints taking `Authorization: Bearer`. Reaches the gateway as a Secret the monitoring module creates. Cannot be combined with `otlp_auth_header_secrets`."
  type        = string
  default     = null
  sensitive   = true
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

# ==============================================================================
# Grafana state database
# ==============================================================================

variable "grafana_database" {
  description = <<-EOT
    Provision a dedicated Azure Database for PostgreSQL Flexible Server for Grafana's own state.

    Grafana keeps users, service accounts and tokens, annotations, dashboard versions and
    permissions, preferences, and alert-rule state in a database separate from the observability
    data in Loki and Thanos. The chart default is SQLite on an `emptyDir`, so all of it is lost on
    every restart, upgrade, and reschedule. That is tolerable while Grafana is reached through
    `port-forward` and not once it is exposed, which is why this and `grafana_load_balancer`
    belong in the same change.

    Dedicated rather than a database inside the Materialize server, deliberately: a Flexible
    Server has one administrator login and no ARM resource for additional roles, so sharing one
    would mean handing Grafana the credentials that also own Materialize's metadata. On its own
    server it *is* the administrator, which is what lets it run its schema migrations at startup.

    `B_Standard_B1ms` is enough. Grafana's state is small and its query rate is a handful per page
    load; this is a durability decision, not a capacity one.

    Null leaves Grafana on SQLite. Point at a database you already run with the
    `grafana_database_*` variables instead.

    The examples enable this whenever `enable_observability` is on: durability is the
    production default, and the cost of the smallest instance is well below the cost of
    silently losing everything a user built in Grafana.
  EOT

  type = object({
    subnet_id           = string
    private_dns_zone_id = string

    sku_name              = optional(string, "B_Standard_B1ms")
    postgres_version      = optional(string, "16")
    storage_mb            = optional(number, 32768)
    backup_retention_days = optional(number, 7)
  })

  default = null

  validation {
    condition     = var.grafana_database == null || var.grafana_database_host == null
    error_message = "Set either grafana_database (this module creates the server) or grafana_database_host (you point at an existing one), not both."
  }
}

# The five below point Grafana at a database this module does not create. They
# are forwarded to the monitoring module untouched, and are mutually exclusive
# with `grafana_database`.

variable "grafana_database_host" {
  description = "FQDN of an existing PostgreSQL server for Grafana's state. Mutually exclusive with `grafana_database`. Host only — the port is `grafana_database_port`."
  type        = string
  default     = null
}

variable "grafana_database_port" {
  description = "Port for `grafana_database_host`."
  type        = number
  default     = 5432
  nullable    = false
}

variable "grafana_database_name" {
  description = "Name of the database Grafana owns."
  type        = string
  default     = "grafana"
  nullable    = false
}

variable "grafana_database_user" {
  description = "Database user Grafana connects as. Defaults to the administrator login of the server this module creates, because Grafana runs schema migrations at startup and a Flexible Server has no ARM resource for creating additional roles."
  type        = string
  default     = "grafana"
  nullable    = false
}

variable "grafana_database_password" {
  description = "Password for `grafana_database_user`. Generated when this module creates the server. Null with an external host means the connection needs no password."
  type        = string
  default     = null
  sensitive   = true
}

variable "grafana_database_ssl_mode" {
  description = "libpq SSL mode for the Grafana database connection. Flexible Server requires TLS, so `disable` will not connect. `require` encrypts but does not authenticate the server; `verify-full` also authenticates it but needs the DigiCert root mounted, which this module does not do — supply `grafana.ini.database.ca_cert_path` and the matching mount through `additional_values` for that."
  type        = string
  default     = "require"
  nullable    = false
}

# ==============================================================================
# Grafana load balancer
# ==============================================================================

variable "grafana_load_balancer" {
  description = <<-EOT
    Expose Grafana through an Azure load balancer, provisioned from the `LoadBalancer` Service the
    chart renders.

    A Service rather than an Ingress: this is the shape AKS takes without an ingress controller
    installed, and it matches what the `load_balancers` module already does for the Materialize
    console. The two are not an L7-versus-L4 choice — both ask Azure for a load balancer — so pick
    by what the cluster's controllers actually consume.

    Internal by default, and `ingress_cidr_blocks` is required rather than defaulted: it becomes
    `loadBalancerSourceRanges` on the Service, and the chart refuses to render a `LoadBalancer`
    with no allowlist. On an internal load balancer pass your VNet CIDR; the chart cannot see the
    `azure-load-balancer-internal` annotation, so the allowlist is what makes the intent legible
    to it.

    `host` is optional because an Azure load balancer answers on an IP. Set it once DNS exists —
    Grafana builds share links, alert notification links, and OAuth redirect URIs from
    `root_url`, and the chart warns while it is unset.

    `ip` pre-allocates the address instead of letting Azure pick one. Supplying it is what makes
    `grafana_url` known at plan time — without it the module has to read the Service back after
    apply, which is why a fresh apply can still report the in-cluster name. For an internal load
    balancer pass a free address from the AKS subnet; for a public one reserve an
    `azurerm_public_ip` in the node resource group.

    Null leaves Grafana on a ClusterIP Service, reachable only with `kubectl port-forward`.
  EOT

  type = object({
    ingress_cidr_blocks = list(string)

    internal    = optional(bool, true)
    host        = optional(string, null)
    ip          = optional(string, null)
    annotations = optional(map(string), {})
  })

  default = null

  validation {
    condition = var.grafana_load_balancer == null ? true : (
      length(var.grafana_load_balancer.ingress_cidr_blocks) > 0 && alltrue([
        for cidr in var.grafana_load_balancer.ingress_cidr_blocks : can(cidrhost(cidr, 0))
      ])
    )
    error_message = "grafana_load_balancer.ingress_cidr_blocks must be non-empty and contain valid CIDR notation. On an internal load balancer, pass your VNet CIDR."
  }


  validation {
    condition = var.grafana_load_balancer == null ? true : (
      var.grafana_load_balancer.internal
      || !anytrue([
        for cidr in coalesce(var.grafana_load_balancer.ingress_cidr_blocks, []) :
        contains(["0.0.0.0/0", "::/0"], trimspace(cidr))
      ])
      # The acknowledgement is the chart's own `connections.grafana.allowPublicAccess`,
      # set through `additional_values` like any other chart value. Deliberately not
      # a variable of its own: there should be exactly one way to say this, and
      # saying it should take a moment's thought.
      || anytrue([
        for doc in var.additional_values :
        try(yamldecode(doc).connections.grafana.allowPublicAccess, false)
      ])
    )
    error_message = <<-EOT
      grafana_load_balancer is public (internal = false) with an unrestricted allowlist (0.0.0.0/0 or ::/0).
      Narrow ingress_cidr_blocks to the ranges that should reach Grafana.
      Every datasource behind Grafana reads every metric in Thanos and every log in the tenant, and
      until an identity provider is configured the generated admin password is the whole of the
      access control — which is why this is refused here but merely defaulted for the Materialize
      load balancers.
      If the allowlist is enforced somewhere this module cannot see, acknowledge it through the
      chart: additional_values = [yamlencode({ connections = { grafana = { allowPublicAccess = true } } })].
    EOT
  }
}
