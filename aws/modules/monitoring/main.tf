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
#   * Bucket lifecycle rules are off by default. Loki and Thanos both enforce
#     their own retention, and Thanos keeps blocks per downsampling resolution
#     (raw / 5m / 1h) — a bucket rule expiring sooner deletes blocks the
#     compactor still references. Use them only as a backstop above that.
#   * Grafana is ClusterIP today (the chart exposes no ingress values yet), so
#     `grafana_url` is in-cluster: reach it with
#     `kubectl -n monitoring port-forward svc/grafana 3000:80` and
#     `terraform output -raw grafana_admin_password`.
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

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
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
  for_each = { for k, v in local.buckets : k => v if v.retention_days != null }

  bucket = aws_s3_bucket.telemetry[each.key].id

  rule {
    id     = "expire-telemetry"
    status = "Enabled"

    filter {}

    expiration {
      days = each.value.retention_days
    }

    # Versioning keeps a copy of every deleted object; without this the bucket
    # grows even as the compactor deletes.
    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
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
}

resource "aws_iam_role_policy" "telemetry" {
  for_each = local.service_accounts

  name   = "${var.name_prefix}-mzmon-${each.key}"
  role   = aws_iam_role.telemetry[each.key].id
  policy = data.aws_iam_policy_document.bucket_access[each.key].json
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
  # The tag's `/` is percent-encoded deliberately. Terraform 1.9 (which CI pins)
  # splits the source on the first `/` inside the `ref` query value, silently
  # truncating it to `?ref=materialize-monitoring` and failing the clone with
  # `pathspec 'materialize-monitoring' did not match`. Newer Terraform parses it
  # correctly, so this only reproduces on the pinned version.
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring%2Fv0.12.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  # Null means "use whatever the pinned module ships with", which is the
  # supported path — the module and the chart are one release.
  chart_version = var.chart_version

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

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

  additional_values = var.additional_values

  depends_on = [
    aws_iam_role_policy.telemetry,
    aws_s3_bucket_public_access_block.telemetry,
  ]
}
