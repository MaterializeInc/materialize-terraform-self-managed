variable "name_prefix" {
  description = "Prefix for the bucket and IAM role names this module creates. Capped at 40 characters so the longest generated name still fits: S3 bucket names are limited to 63, and `-mzmon-metrics-` plus the 8-character random suffix takes 23."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name_prefix) <= 40
    error_message = "name_prefix must be at most 40 characters; S3 bucket names are capped at 63 and `-mzmon-metrics-` plus the random suffix uses 23."
  }
}

variable "region" {
  description = "AWS region the buckets live in. Passed explicitly rather than read from a data source, matching the rest of this repository."
  type        = string
  nullable    = false
}

variable "namespace" {
  description = "Namespace the monitoring stack is installed into. Also the namespace half of every IRSA trust-policy subject."
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

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider, from the EKS module."
  type        = string
  nullable    = false
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster, from the EKS module."
  type        = string
  nullable    = false
}

variable "iam_permissions_boundary" {
  description = "Optional permissions boundary applied to the IAM roles this module creates. No other AWS module in this repository takes one yet; the intent is that they should, and this is the first. Leaving it null keeps the previous behaviour, so adding it elsewhere later is additive."
  type        = string
  default     = null
}

# ==============================================================================
# Buckets
# ==============================================================================

variable "bucket_force_destroy" {
  description = "Allow Terraform to delete non-empty buckets. Leave false outside throwaway environments — destroying it takes the telemetry with it."
  type        = bool
  default     = false
  nullable    = false
}

variable "bucket_encryption_mode" {
  description = "Server-side encryption for the telemetry buckets. SSE-S3 by default; SSE-KMS requires `bucket_kms_key_arn` and grants the two backend roles `kms:Decrypt` and `kms:GenerateDataKey` on that key. Matches the option `aws/modules/storage` offers for the Materialize persist bucket."
  type        = string
  default     = "SSE-S3"
  nullable    = false

  validation {
    condition     = contains(["SSE-S3", "SSE-KMS"], var.bucket_encryption_mode)
    error_message = "bucket_encryption_mode must be either \"SSE-S3\" or \"SSE-KMS\"."
  }
}

variable "bucket_kms_key_arn" {
  description = "ARN of the KMS key to use when `bucket_encryption_mode` is SSE-KMS. A customer-managed key, not an alias — the IAM grant needs the ARN. Bucket Keys are enabled alongside it, because both backends write enough small objects for per-object KMS calls to show up on the bill."
  type        = string
  default     = null
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the telemetry buckets. Versioning is the disaster-recovery primitive for both Loki and Thanos, neither of which has a native snapshot."
  type        = bool
  default     = true
  nullable    = false
}

variable "logs_retention_days" {
  description = "Expire Loki objects after this many days. Null disables the lifecycle rule and leaves retention entirely to Loki's compactor."
  type        = number
  default     = null
}

variable "metrics_retention_days" {
  description = <<-EOT
    Expire Thanos objects after this many days. Null disables the lifecycle rule.

    Leave it null unless you know what you are doing: Thanos's compactor already enforces
    retention per downsampling resolution (raw / 5m / 1h), and a bucket rule that expires
    sooner deletes blocks the compactor still expects to find.
  EOT
  type        = number
  default     = null
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
  description = "StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos receive/compactor/store-gateway). Null uses whatever class the cluster marks default; the examples pass the `gp3` class from the `ebs-csi-driver` module."
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

# ==============================================================================
# Grafana state database
# ==============================================================================

variable "grafana_database" {
  description = <<-EOT
    Provision a dedicated RDS PostgreSQL instance for Grafana's own state.

    Grafana keeps users, service accounts and tokens, annotations, dashboard versions and
    permissions, preferences, and alert-rule state in a database separate from the observability
    data in Loki and Thanos. The chart default is SQLite on an `emptyDir`, so all of it is lost on
    every restart, upgrade, and reschedule. That is tolerable while Grafana is reached through
    `port-forward` and not once it is exposed, which is why this and `grafana_load_balancer` belong in
    the same change.

    Dedicated rather than a database inside the Materialize RDS instance, deliberately: RDS has no
    API for creating a second database in an existing instance, so sharing one would need the
    PostgreSQL provider to reach a private endpoint from wherever Terraform runs. A separate
    instance also keeps Grafana's blast radius away from Materialize's metadata.

    `db.t4g.micro` is enough. Grafana's state is small and its query rate is a handful per page
    load; this is a durability decision, not a capacity one.

    Null leaves Grafana on SQLite. Point at a database you already run with the
    `grafana_database_*` variables instead.

    The examples enable this whenever `enable_observability` is on: durability is the
    production default, and the cost of the smallest instance is well below the cost of
    silently losing everything a user built in Grafana.
  EOT

  type = object({
    vpc_id                    = string
    subnet_ids                = list(string)
    cluster_name              = string
    cluster_security_group_id = string
    node_security_group_id    = string

    instance_class          = optional(string, "db.t4g.micro")
    postgres_version        = optional(string, "16")
    allocated_storage       = optional(number, 20)
    max_allocated_storage   = optional(number, 100)
    multi_az                = optional(bool, false)
    backup_retention_period = optional(number, 7)
    kms_key_id              = optional(string, null)
    create_kms_key          = optional(bool, true)
    # Matches the shared `database` module's own default. The enterprise example
    # flips it, so a production teardown leaves a recovery snapshot behind.
    skip_final_snapshot = optional(bool, true)
  })

  default = null

  validation {
    condition     = var.grafana_database == null || var.grafana_database_host == null
    error_message = "Set either grafana_database (this module creates the instance) or grafana_database_host (you point at an existing one), not both."
  }
}

# The five below point Grafana at a database this module does not create. They
# are forwarded to the monitoring module untouched, and are mutually exclusive
# with `grafana_database`.

variable "grafana_database_host" {
  description = "Hostname of an existing PostgreSQL database for Grafana's state. Mutually exclusive with `grafana_database`. Host only — the port is `grafana_database_port`."
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
  description = "Database user Grafana connects as. Must own `grafana_database_name`: Grafana runs schema migrations at startup, so a read/write-only grant fails them."
  type        = string
  default     = "grafana"
  nullable    = false
}

variable "grafana_database_password" {
  description = "Password for `grafana_database_user`. Generated when this module creates the instance. Null with an external host means the connection needs no password."
  type        = string
  default     = null
  sensitive   = true
}

variable "grafana_database_ssl_mode" {
  description = "libpq SSL mode for the Grafana database connection. `require` encrypts but does not authenticate the server; `verify-full` also authenticates it but needs the RDS CA bundle mounted, which this module does not do — supply `grafana.ini.database.ca_cert_path` and the matching mount through `additional_values` for that."
  type        = string
  default     = "require"
  nullable    = false
}

# ==============================================================================
# Grafana ingress
# ==============================================================================

variable "grafana_load_balancer" {
  description = <<-EOT
    Expose Grafana through a Network Load Balancer, provisioned by the AWS Load Balancer Controller
    from the `LoadBalancer` Service the chart renders. The controller must already be installed —
    the examples install it as `module.aws_lbc`.

    L4, matching the GCP and Azure wrappers and the Materialize console. An earlier revision used an
    Ingress here, which the controller turns into an L7 ALB — but that made AWS the only cloud
    running L7 while a `Service` on GKE and AKS can only ever produce L4, so the three disagreed
    about what "exposed" meant. L7 is the better end state for a public Grafana, because a WAF and
    edge authentication are the two things L4 cannot do at all; it is deferred rather than rejected.
    See the design note in the repository README.

    Internal by default, and `ingress_cidr_blocks` is required rather than defaulted: it becomes
    `loadBalancerSourceRanges` on the Service, and the chart refuses to render a `LoadBalancer` with
    no allowlist. On an internal load balancer pass your VPC CIDR; the chart cannot see the scheme
    annotation, so the allowlist is what makes the intent legible to it.

    `host` is optional because an NLB answers on a DNS name of its own. Set it once your own DNS
    exists — Grafana builds share links, alert notification links, and OAuth redirect URIs from
    `root_url`, and the chart warns while it is unset.

    **This does not terminate TLS.** An NLB passes bytes through, so Grafana serves plain HTTP until
    something in front of it, or Grafana itself, is given a certificate — which is DEP-195's work.
    Until then the chart warns, and `root_url`/`security.cookie_secure` are yours to set through
    `additional_values` if you do put a terminator in front.

    `ip` pins the load balancer's addresses rather than letting AWS pick them, which is what makes
    them safe to name in a firewall rule or a DNS record. On an internal NLB pass one private
    address per subnet the load balancer lands in, each inside that subnet's CIDR; on an
    internet-facing one pass Elastic IP allocation IDs. Both are comma-separated, matching the AWS
    annotations they become.

    It does **not** make `grafana_url` deterministic, unlike on GCP and Azure. An NLB is reached by a
    generated DNS name that pinning addresses does not predict, so the module still reads the Service
    back after apply. Set `host` for a deterministic URL on AWS.

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
    error_message = "grafana_load_balancer.ingress_cidr_blocks must be non-empty and contain valid CIDR notation. On an internal load balancer, pass your VPC CIDR."
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

variable "additional_values" {
  description = "Raw YAML documents appended to the Helm values, last, so they override everything the modules compute."
  type        = list(string)
  default     = []
  nullable    = false
}
