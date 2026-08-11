# Deploys the `materialize-monitoring` observability stack on EKS: Grafana
# dashboards, Prometheus-compatible metrics via Thanos, logs via Loki, and the
# Alloy collection pipeline.
#
# This module owns the AWS side — one S3 bucket per backend and an IRSA role per
# backend — and delegates everything inside the cluster to the cloud-agnostic
# module that ships alongside the chart in the `materialize-monitoring`
# repository. Nothing here names a Helm value path; that knowledge lives next to
# the chart, so a chart change and its Terraform consequence land together.
#
# Replaces the previous `kubernetes/modules/prometheus` and
# `kubernetes/modules/grafana`, which vendored a point-in-time dashboard copy and
# a legacy scrape config, collected metrics only, and ran a single Prometheus on
# a ReadWriteOnce volume with 15 days of retention.
#
# Operational notes:
#
#   * The `monitoring` namespace is created by the operator module in the
#     supported topology, so `create_namespace` defaults to false. Keep a
#     `depends_on` for the operator or the release can race the namespace.
#   * The operator module also installs metrics-server, which the Materialize
#     Console depends on for cluster metrics. If you disable it there, set
#     `install_metrics_server = true` here in the same change.
#   * Bucket *retention* is off by default, but housekeeping always runs.
#     Aborting incomplete multipart uploads and expiring noncurrent versions are
#     unconditional, because nothing else ever reclaims either and both grow
#     without bound. Only `logs_retention_days` / `metrics_retention_days` are
#     opt-in: Loki and Thanos both enforce their own retention, and Thanos keeps
#     blocks per downsampling resolution (raw / 5m / 1h), so a bucket rule
#     expiring sooner deletes blocks the compactor still references. Use those
#     two only as a backstop above what the compactors already do.
#   * Grafana is ClusterIP until `grafana_load_balancer` is set, so `grafana_url`
#     is in-cluster by default: reach it with
#     `kubectl -n monitoring port-forward svc/grafana 3000:80` and
#     `terraform output -raw grafana_admin_password`. With a load balancer,
#     `grafana_url` names its address, and DNS for any hostname is yours.
#   * That load balancer is an L4 NLB, matching GCP, Azure, and the Materialize
#     console. It terminates no TLS — see `grafana_load_balancer`.
#   * `grafana_load_balancer` and `grafana_database` belong together. Exposing Grafana
#     without a durable backend turns a bundled extra nobody depended on into the
#     primary interface to the stack — one that discards every dashboard,
#     annotation, and API token its users create on the next restart.
#   * `node_selector` reaches every centralized workload but deliberately not
#     the Alloy agent DaemonSet, which must run on every node to collect from
#     it. `tolerations` do reach the agent, since they widen rather than narrow
#     where a pod may run.
#
# One bucket per backend rather than one shared with prefixes: Loki and Thanos
# want different lifecycle rules, IAM scoping is tighter, and Loki's
# `bucketNames` are bucket names rather than prefixes.

locals {
  # The chart renders deterministic ServiceAccount names, and the trust policies
  # below have to match them exactly. The monitoring module emits the resolved
  # subjects as an output; these are the same names, needed here before that
  # module exists — passing them the other way would close a dependency cycle.
  service_accounts = {
    loki   = "loki"
    thanos = "thanos-thanos"
  }

  oidc_issuer_host = trimprefix(var.cluster_oidc_issuer_url, "https://")

  bucket_encryption_uses_kms = var.bucket_encryption_mode == "SSE-KMS"

  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Component = "materialize-monitoring"
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ==============================================================================
# Buckets
# ==============================================================================

locals {
  buckets = {
    loki = {
      name           = "${var.name_prefix}-mzmon-logs-${random_id.bucket_suffix.hex}"
      retention_days = var.logs_retention_days
    }
    thanos = {
      name           = "${var.name_prefix}-mzmon-metrics-${random_id.bucket_suffix.hex}"
      retention_days = var.metrics_retention_days
    }
  }
}

resource "aws_s3_bucket" "telemetry" {
  for_each = local.buckets

  bucket        = each.value.name
  force_destroy = var.bucket_force_destroy

  tags = merge(local.common_tags, { Backend = each.key })
}

resource "aws_s3_bucket_public_access_block" "telemetry" {
  for_each = aws_s3_bucket.telemetry

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "telemetry" {
  for_each = aws_s3_bucket.telemetry

  bucket = each.value.id

  lifecycle {
    precondition {
      condition     = !(local.bucket_encryption_uses_kms && var.bucket_kms_key_arn == null)
      error_message = "Set bucket_kms_key_arn when bucket_encryption_mode is SSE-KMS."
    }
  }

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.bucket_encryption_uses_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.bucket_encryption_uses_kms ? var.bucket_kms_key_arn : null
    }

    # S3 Bucket Keys cut KMS request volume, and therefore KMS billing, by
    # reusing one data key across many objects instead of calling KMS per
    # object. Both backends write a very large number of small objects, so this
    # is the difference between a rounding error and a line item.
    bucket_key_enabled = local.bucket_encryption_uses_kms
  }
}

resource "aws_s3_bucket_versioning" "telemetry" {
  for_each = var.enable_bucket_versioning ? aws_s3_bucket.telemetry : {}

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Retention here is a backstop, not the primary control: Loki's compactor and
# Thanos's compactor both enforce their own. A bucket rule that expires sooner
# than they expect deletes blocks they still reference.
resource "aws_s3_bucket_lifecycle_configuration" "telemetry" {
  for_each = local.buckets

  bucket = aws_s3_bucket.telemetry[each.key].id

  # Housekeeping is unconditional. It used to live inside the retention rule,
  # which meant the whole configuration was skipped whenever `retention_days` was
  # null — the default — so the two cleanups below silently never ran.

  # An interrupted multipart upload leaves parts that are billed and do not show
  # up in a normal object listing, so nothing else ever reclaims them. Both
  # backends use multipart uploads for large blocks and chunks.
  rule {
    id     = "abort-incomplete-multipart-upload"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Versioning keeps a copy of every object the compactors delete, and both of
  # them delete constantly. Without this the bucket grows without bound even
  # though retention appears to be working.
  #
  # Unconditional rather than gated on `enable_bucket_versioning`, because S3
  # versioning cannot be turned back off — destroying the versioning resource
  # *suspends* it, which stops new versions but keeps every one already written.
  # Gating this rule on the same variable would remove the only thing that
  # expires them in the very apply that suspends versioning, stranding them
  # permanently. On a bucket that was never versioned the rule simply never
  # matches.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  # Retention itself is a backstop, not the primary control — see the header.
  # Off by default, which is why it has to be the conditional part rather than
  # the gate on everything else.
  dynamic "rule" {
    for_each = each.value.retention_days == null ? [] : [each.value.retention_days]

    content {
      id     = "expire-telemetry"
      status = "Enabled"

      filter {}

      expiration {
        days = rule.value
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.telemetry]
}

# ==============================================================================
# IRSA
# ==============================================================================

data "aws_iam_policy_document" "assume_role" {
  for_each = local.service_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${each.value}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "telemetry" {
  for_each = local.service_accounts

  name                 = "${var.name_prefix}-mzmon-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.assume_role[each.key].json
  permissions_boundary = var.iam_permissions_boundary

  tags = merge(local.common_tags, { Backend = each.key })
}

# Scoped to the one bucket that backend owns.
data "aws_iam_policy_document" "bucket_access" {
  for_each = local.service_accounts

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.telemetry[each.key].arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.telemetry[each.key].arn}/*"]
  }

  # Thanos and Loki both use multipart uploads for large blocks and chunks.
  statement {
    effect    = "Allow"
    actions   = ["s3:AbortMultipartUpload", "s3:ListMultipartUploadParts", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.telemetry[each.key].arn, "${aws_s3_bucket.telemetry[each.key].arn}/*"]
  }

  # Bucket permissions alone are not enough under SSE-KMS: S3 evaluates the key
  # policy separately, so without this every PutObject fails with AccessDenied
  # and every GetObject fails to decrypt — while the bucket policy above looks
  # entirely correct. GenerateDataKey covers writes, Decrypt covers reads, and
  # both are needed for multipart.
  dynamic "statement" {
    for_each = local.bucket_encryption_uses_kms ? [var.bucket_kms_key_arn] : []

    content {
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "telemetry" {
  for_each = local.service_accounts

  name   = "${var.name_prefix}-mzmon-${each.key}"
  role   = aws_iam_role.telemetry[each.key].id
  policy = data.aws_iam_policy_document.bucket_access[each.key].json
}

# ==============================================================================
# Grafana state database
# ==============================================================================
# Reuses this repo's own `database` module rather than an inline `aws_db_instance`,
# so Grafana's instance gets the same KMS, security-group, subnet-group, and
# backup opinions the Materialize database already has.
#
# Grafana connects as the instance's master user, which on a dedicated instance
# is the simplest thing that satisfies the requirement that it *own* its
# database — schema migrations run at every startup.

resource "random_password" "grafana_database" {
  count = var.grafana_database != null && var.grafana_database_password == null ? 1 : 0

  length = 32
  # RDS rejects several punctuation characters in a master password, and Grafana
  # reads this out of a mounted file that operators also paste into psql.
  # Alphanumeric avoids both problems.
  special = false
}

module "grafana_database" {
  count  = var.grafana_database == null ? 0 : 1
  source = "../database"

  name_prefix = "${var.name_prefix}-mzmon-grafana"

  postgres_version      = var.grafana_database.postgres_version
  instance_class        = var.grafana_database.instance_class
  allocated_storage     = var.grafana_database.allocated_storage
  max_allocated_storage = var.grafana_database.max_allocated_storage
  multi_az              = var.grafana_database.multi_az

  database_name     = var.grafana_database_name
  database_username = var.grafana_database_user
  database_password = local.grafana_database_password

  database_subnet_ids       = var.grafana_database.subnet_ids
  vpc_id                    = var.grafana_database.vpc_id
  cluster_name              = var.grafana_database.cluster_name
  cluster_security_group_id = var.grafana_database.cluster_security_group_id
  node_security_group_id    = var.grafana_database.node_security_group_id

  backup_retention_period = var.grafana_database.backup_retention_period
  create_kms_key          = var.grafana_database.create_kms_key
  kms_key_id              = var.grafana_database.kms_key_id
  skip_final_snapshot     = var.grafana_database.skip_final_snapshot

  tags = merge(local.common_tags, { Backend = "grafana" })
}

locals {
  create_grafana_database = var.grafana_database != null

  # A caller-supplied password wins in both modes; the random one only fills the
  # gap when this module creates the instance and was given none.
  #
  # Not `coalesce`: it errors when every argument is null, which is the default
  # install — no database and no password — so it failed the plan on the one path
  # that has nothing to decide. Null here means "no password", which is what the
  # module's own gates are for.
  grafana_database_password = (
    var.grafana_database_password != null
    ? var.grafana_database_password
    : one(random_password.grafana_database[*].result)
  )

  # `db_instance_endpoint` is already `host:port`, so it is split rather than
  # re-joined — the module's own port is authoritative over any default here.
  grafana_database_host = local.create_grafana_database ? (
    split(":", module.grafana_database[0].db_instance_endpoint)[0]
  ) : var.grafana_database_host

  grafana_database_port = local.create_grafana_database ? (
    module.grafana_database[0].db_instance_port
  ) : var.grafana_database_port

  # Null means "no password", which is a legitimate shape for an external host
  # behind peer authentication or a proxy. Never null for an instance this
  # module creates.
  grafana_database_effective_password = (
    local.create_grafana_database ? local.grafana_database_password : var.grafana_database_password
  )
}

# ==============================================================================
# Grafana load balancer
# ==============================================================================

locals {
  # Plain http, always. An NLB is L4 — it passes bytes through and terminates
  # nothing — so claiming https here would only advertise a scheme that does not
  # answer, and the `cookie_secure` that would come with it makes the session
  # cookie unsendable over the connection that does work.
  #
  # Put a terminator in front, or give Grafana its own certificate (DEP-195), and
  # set `root_url` plus `security.cookie_secure` through `additional_values`.
  grafana_scheme = "http"

  grafana_service_annotations = var.grafana_load_balancer == null ? {} : merge(
    {
      # `external` is what hands the Service to the AWS Load Balancer Controller
      # rather than the in-tree provider, which is the difference between an NLB
      # and a legacy Classic ELB. `ip` targets the pods directly, skipping the
      # NodePort hop, and matches the target type the console's NLB module uses.
      "service.beta.kubernetes.io/aws-load-balancer-type"                 = "external"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"      = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"               = var.grafana_load_balancer.internal ? "internal" : "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "HTTP"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path"     = "/api/health"
    },
    var.grafana_load_balancer.ip == null ? {} : {
      # An NLB takes its addresses by annotation rather than `loadBalancerIP`:
      # one per subnet, so both of these are comma-separated lists.
      (var.grafana_load_balancer.internal
        ? "service.beta.kubernetes.io/aws-load-balancer-private-ipv4-addresses"
      : "service.beta.kubernetes.io/aws-load-balancer-eip-allocations") = var.grafana_load_balancer.ip
    },
    var.grafana_load_balancer.annotations,
  )

  grafana_load_balancer_values = var.grafana_load_balancer == null ? [] : [yamlencode({
    grafana = merge(
      {
        service = {
          type                     = "LoadBalancer"
          annotations              = local.grafana_service_annotations
          loadBalancerSourceRanges = var.grafana_load_balancer.ingress_cidr_blocks
        }
      },
      var.grafana_load_balancer.host == null ? {} : {
        "grafana.ini" = {
          # Grafana builds share links, alert notification links, and OAuth
          # redirect URIs from this. All three break silently when it disagrees
          # with the host users actually reach.
          server = { root_url = "${local.grafana_scheme}://${var.grafana_load_balancer.host}" }
        }
      },
    )
  })]
}

# The load balancer's own address, so `grafana_url` can name where Grafana
# actually answers rather than falling back to the in-cluster Service whenever no
# hostname was supplied.
#
# A data source rather than a resource attribute: the Service is created by Helm
# inside the monitoring module, so Terraform has no handle on it. Read after that
# module, and tolerant of an address that is not assigned yet — the cloud
# provisions the load balancer asynchronously, so the first apply can complete
# before one exists. `grafana_url` degrades to the in-cluster name in that
# window, and the next plan picks the address up.
data "kubernetes_service" "grafana" {
  # Still read even when `ip` is set, unlike GCP and Azure: an NLB is reached by
  # its generated DNS name, and pinning its addresses does not make that name
  # predictable. On AWS, determinism comes from `host` — your own record
  # pointing at the NLB — not from the addresses.
  count = var.grafana_load_balancer == null ? 0 : 1

  metadata {
    # The chart pins `grafana.fullnameOverride`, so the name is static.
    name      = "grafana"
    namespace = var.namespace
  }

  depends_on = [module.monitoring]
}

locals {
  # An NLB reports a `hostname`; the `ip` branch is there for a Service given a
  # static address by annotation.
  grafana_load_balancer_address = one([
    for ing in try(data.kubernetes_service.grafana[0].status[0].load_balancer[0].ingress, []) :
    coalesce(try(ing.hostname, null), try(ing.ip, null))
    if coalesce(try(ing.hostname, null), try(ing.ip, null), "") != ""
  ])
}

# ==============================================================================
# The stack
# ==============================================================================

module "monitoring" {
  # Pinned to a released tag. The module and the chart it installs are one
  # release, and the module reads its chart version out of the chart beside it —
  # so this ref alone names the chart version, with nothing to keep in sync.
  #
  # Developing against an unreleased module: point this at a local checkout
  # (`../../../../materialize-monitoring/terraform/modules/materialize-monitoring`)
  # for the duration. It must stay a *relative* path — an absolute one makes
  # Terraform copy the module without the chart directory beside it, and the
  # sizing profiles stop resolving.
  #
  # The `/` in the tag name is why this module floors at Terraform 1.10. Before
  # that fix, Terraform truncated the ref at the first slash and treated the rest
  # as a subdirectory, failing the clone with `pathspec 'materialize-monitoring'
  # did not match` (hashicorp/terraform#35552). See versions.tf.
  #
  # v0.13.0 is where `grafana_database_*` and the chart's `grafana.ingress` /
  # `grafana.service` values land. This branch does not plan against v0.12.0.
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.15.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  # Null means "use whatever the pinned module ships with", which is the
  # supported path — the module and the chart are one release.
  chart_version = var.chart_version

  # Null on any of these means "use the monitoring module's own default": each
  # is declared `nullable = false` with a default there, and Terraform
  # substitutes the default when a caller passes null. None of the three is
  # reachable through `additional_values`, so without forwarding them a mirrored
  # registry or a cluster that already owns the CRDs has no way through.
  chart_registry         = var.chart_registry
  enable_monitoring_crds = var.enable_monitoring_crds
  install_timeout        = var.install_timeout

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

  # Explicit rather than inferred from host/password: both are computed here — an
  # instance endpoint and a generated password — so the module cannot decide
  # whether they exist at plan time. These two conditions are plan-known.
  grafana_database_enabled                = local.create_grafana_database || var.grafana_database_host != null
  grafana_database_manage_password_secret = local.create_grafana_database || var.grafana_database_password != null

  grafana_database_host     = local.grafana_database_host
  grafana_database_port     = local.grafana_database_port
  grafana_database_name     = var.grafana_database_name
  grafana_database_user     = var.grafana_database_user
  grafana_database_password = local.grafana_database_effective_password
  grafana_database_ssl_mode = var.grafana_database_ssl_mode

  object_storage = {
    cloud         = "aws"
    loki_bucket   = aws_s3_bucket.telemetry["loki"].id
    thanos_bucket = aws_s3_bucket.telemetry["thanos"].id
    region        = var.region
    endpoint      = "s3.${var.region}.amazonaws.com"

    loki_service_account_annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.telemetry["loki"].arn
    }
    thanos_service_account_annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.telemetry["thanos"].arn
    }
  }

  # Ingress values ahead of the caller's, so `additional_values` still overrides
  # anything computed here.
  additional_values = concat(local.grafana_load_balancer_values, var.additional_values)

  depends_on = [
    aws_iam_role_policy.telemetry,
    aws_s3_bucket_public_access_block.telemetry,
  ]
}
