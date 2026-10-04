# Deploys the `materialize-monitoring` stack on EKS: Grafana, metrics via Thanos,
# logs via Loki, and the Alloy pipeline. This module owns the AWS side (an S3
# bucket and IRSA role per backend) and delegates everything in the cluster to
# the cloud-agnostic module shipped with the chart, so no Helm value paths live here.
#
# Moving the buckets into the account regional namespace (v13.0.0) replaces both
# of them; see the v13.0.0 upgrade notes in the root README before applying.
#
# Operational notes:
#
#   * The `monitoring-crds` module creates the `monitoring` namespace and the
#     CRDs, so `create_namespace` defaults to false and the examples pass
#     `enable_monitoring_crds = false`. Pass its `namespace` output as
#     `namespace` (or keep a `depends_on`) or the release can race the namespace.
#   * The operator module installs metrics-server, which the Console needs. If
#     you disable it there, set `install_metrics_server = true` here.
#   * Bucket housekeeping (aborting incomplete multipart uploads, expiring
#     noncurrent versions) always runs. `logs_retention_days` and
#     `metrics_retention_days` are opt-in backstops only: Loki and Thanos enforce
#     their own retention, and Thanos keeps blocks per downsampling resolution
#     (raw / 5m / 1h), so expiring sooner deletes blocks the compactor still needs.
#   * Grafana is ClusterIP unless `grafana_load_balancer` is set. Reach it with
#     `kubectl -n monitoring port-forward svc/grafana 3000:80` and
#     `terraform output -raw grafana_admin_password`. DNS for a hostname is yours.
#   * The load balancer is an L4 NLB and terminates no TLS.
#   * Set `grafana_database` along with `grafana_load_balancer`: without it Grafana
#     loses every dashboard, annotation, and API token on restart.
#   * `node_selector` skips the Alloy agent DaemonSet, which must run on every
#     node. `tolerations` do reach it.
#
# One bucket per backend rather than shared with prefixes: lifecycle rules differ,
# IAM scoping is tighter, and Loki's `bucketNames` are not prefixes.

locals {
  # Must match the chart's ServiceAccount names for the trust policies below. The
  # monitoring module outputs them too, but reading that would be a dependency cycle.
  service_accounts = {
    loki   = "loki"
    thanos = "thanos-thanos"
  }

  # The gateway reads CloudWatch, not a bucket, so it gets its own role and policy
  # but shares the trust-policy document, which is keyed by this merged map.
  gateway_service_account  = "alloy-gateway"
  provider_metrics_enabled = var.provider_metrics != null
  irsa_service_accounts = merge(
    local.service_accounts,
    local.provider_metrics_enabled ? { gateway = local.gateway_service_account } : {},
  )

  oidc_issuer_host = trimprefix(var.cluster_oidc_issuer_url, "https://")

  bucket_encryption_uses_kms = var.bucket_encryption_mode == "SSE-KMS"

  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Component = "materialize-monitoring"
  })
}

# ==============================================================================
# Buckets
# ==============================================================================
# Buckets live in the account regional namespace (house policy), which reserves
# the name to this account. The provider does not append the
# `-{account}-{region}-an` suffix, so it is built here; CreateBucket fails without it.

locals {
  # No account regional namespace here yet, so these keep the global namespace
  # and a random suffix. Removing a region replaces its buckets: a breaking change.
  regions_without_account_regional_namespace = ["me-south-1", "me-central-1"]

  use_account_regional_bucket_namespace = !contains(
    local.regions_without_account_regional_namespace, var.region
  )

  # Up to 31 characters (12 for the account, up to 14 for the region), hence the
  # tight `name_prefix` limit and the precondition below. `account_id` is a
  # variable, not a data source: a caller's `depends_on` would defer a data source
  # to apply time, and an unknown bucket name forces a replacement.
  bucket_name_suffix = (
    local.use_account_regional_bucket_namespace
    ? "-${var.account_id}-${var.region}-an"
    : "-${one(random_id.bucket_suffix[*].hex)}"
  )

  buckets = {
    loki = {
      name           = "${var.name_prefix}-mzmon-logs${local.bucket_name_suffix}"
      retention_days = var.logs_retention_days
    }
    thanos = {
      name           = "${var.name_prefix}-mzmon-metrics${local.bucket_name_suffix}"
      retention_days = var.metrics_retention_days
    }
  }
}

# Global namespace only, where names compete across all AWS accounts. The
# regional namespace needs no disambiguation and has no room left for it.
resource "random_id" "bucket_suffix" {
  count = local.use_account_regional_bucket_namespace ? 0 : 1

  byte_length = 4
}

resource "aws_s3_bucket" "telemetry" {
  for_each = local.buckets

  bucket = each.value.name
  # Null, not "global", on the fallback path: the argument is computed and forces
  # replacement, so letting the API fill it keeps older buckets out of the diff.
  bucket_namespace = local.use_account_regional_bucket_namespace ? "account-regional" : null
  force_destroy    = var.bucket_force_destroy

  tags = merge(local.common_tags, { Backend = each.key })

  # Fail at plan rather than mid-apply at CreateBucket. Checks the built name, so
  # it covers both namespaces.
  lifecycle {
    precondition {
      condition     = length(each.value.name) <= 63
      error_message = "Bucket name \"${each.value.name}\" is ${length(each.value.name)} characters and S3 caps them at 63. Shorten name_prefix by ${max(0, length(each.value.name) - 63)}."
    }
  }
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

    # Bucket Keys reuse one data key across objects instead of calling KMS per
    # object. Both backends write many small objects, so this cuts KMS cost a lot.
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

resource "aws_s3_bucket_lifecycle_configuration" "telemetry" {
  for_each = local.buckets

  bucket = aws_s3_bucket.telemetry[each.key].id

  # Interrupted multipart uploads leave billed parts that do not show in object
  # listings, so nothing else reclaims them.
  rule {
    id     = "abort-incomplete-multipart-upload"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Versioning keeps a copy of everything the compactors delete; without this the
  # bucket grows without bound. Not gated on `enable_bucket_versioning`: turning
  # it off only suspends versioning and keeps old versions, which gating would
  # strand. On a never-versioned bucket the rule never matches.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  # Opt-in retention backstop; see the notes at the top of this file.
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
  for_each = local.irsa_service_accounts

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

  # Under SSE-KMS the key is authorized separately: without this, writes fail with
  # AccessDenied and reads cannot decrypt. GenerateDataKey covers writes, Decrypt
  # covers reads, and multipart needs both.
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
# Provider metrics: the gateway reads CloudWatch
# ==============================================================================
# Only what the chart's CloudWatch pull calls. RDS and S3 jobs are `static`
# (GetMetricStatistics); the exporter also reads the account alias for labels.
# EKS nodes are replaced too often to name, so EKS jobs discover them by tag
# (`aws:eks:cluster-name` on nodes, `eks:cluster-name` on node group ASGs) and
# read them with ListMetrics and GetMetricData. Those four actions are granted
# only when a cluster is listed.
#
# Every action is `Resource: "*"`: none supports resource types or condition
# keys. The chart values do the scoping instead.

resource "aws_iam_role" "gateway" {
  count = local.provider_metrics_enabled ? 1 : 0

  name                 = "${var.name_prefix}-mzmon-gateway"
  assume_role_policy   = data.aws_iam_policy_document.assume_role["gateway"].json
  permissions_boundary = var.iam_permissions_boundary

  tags = merge(local.common_tags, { Backend = "gateway" })
}

data "aws_iam_policy_document" "provider_metrics_read" {
  count = local.provider_metrics_enabled ? 1 : 0

  statement {
    sid       = "CloudWatchRead"
    effect    = "Allow"
    actions   = ["cloudwatch:GetMetricStatistics"]
    resources = ["*"]
  }

  statement {
    sid       = "AccountAlias"
    effect    = "Allow"
    actions   = ["iam:ListAccountAliases"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.provider_metrics.eks_cluster_names) > 0 ? [1] : []

    content {
      sid    = "EksNodeDiscovery"
      effect = "Allow"
      actions = [
        "autoscaling:DescribeAutoScalingGroups",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics",
        "tag:GetResources",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "gateway" {
  count = local.provider_metrics_enabled ? 1 : 0

  name   = "${var.name_prefix}-mzmon-gateway"
  role   = aws_iam_role.gateway[0].id
  policy = data.aws_iam_policy_document.provider_metrics_read[0].json
}

# ==============================================================================
# Grafana state database
# ==============================================================================
# Uses this repo's `database` module so Grafana's instance gets the same KMS,
# security-group, subnet-group, and backup settings as the Materialize database.
# Grafana connects as the master user because it must own its database to run
# schema migrations at startup.

resource "random_password" "grafana_database" {
  count = var.grafana_database != null && var.grafana_database_password == null ? 1 : 0

  length = 32
  # RDS rejects some punctuation in master passwords, and Grafana reads this
  # from a mounted file that operators paste into psql. Alphanumeric avoids both.
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

  # A caller-supplied password wins; the random one is used only when this module
  # creates the instance. Not `coalesce`, which errors when every argument is
  # null, as in the default install with no database.
  grafana_database_password = (
    var.grafana_database_password != null
    ? var.grafana_database_password
    : one(random_password.grafana_database[*].result)
  )

  # `db_instance_endpoint` is `host:port`; keep the host and take the port from
  # the module's own output.
  grafana_database_host = local.create_grafana_database ? (
    split(":", module.grafana_database[0].db_instance_endpoint)[0]
  ) : var.grafana_database_host

  grafana_database_port = local.create_grafana_database ? (
    module.grafana_database[0].db_instance_port
  ) : var.grafana_database_port

  # Null is valid for an external host behind peer auth or a proxy. Never null
  # for an instance this module creates.
  grafana_database_effective_password = (
    local.create_grafana_database ? local.grafana_database_password : var.grafana_database_password
  )
}

# ==============================================================================
# Grafana load balancer
# ==============================================================================
# Copied from `aws/modules/nlb` rather than calling it: that module is keyed on a
# Materialize instance's `resource_id`, so monitoring would wait for Materialize.
# Not `service.type: LoadBalancer` with annotations: reading the address back
# from the Service races the controller, and annotations are untyped strings.

locals {
  grafana_lb = var.grafana_load_balancer
  # `aws_lb` and `aws_lb_target_group` cap `name_prefix` at 6 characters (the whole
  # prefix) and `name` at 32. A generated name avoids collisions between
  # deployments whose truncated prefixes match, since LB names are unique per
  # account and region, and allows `create_before_destroy`. `grafana_nlb_name`
  # overrides it.
  grafana_lb_name_prefix = substr(var.name_prefix, 0, min(6, length(var.name_prefix)))

  # Grafana's container port. The target group registers pod IPs, so this, not
  # the Service port, is what matters.
  grafana_pod_port = 3000

  grafana_lb_listener_port = try(local.grafana_lb.listener_port, 80)

  # Pre-allocated addresses become `subnet_mapping` blocks, which are mutually
  # exclusive with `subnets`.
  grafana_lb_addresses = local.grafana_lb == null ? null : coalesce(
    local.grafana_lb.private_ipv4_addresses,
    local.grafana_lb.eip_allocation_ids,
    [],
  )

  grafana_lb_subnet_mappings = try(length(local.grafana_lb_addresses), 0) == 0 ? [] : [
    for i, subnet in local.grafana_lb.subnet_ids : {
      subnet_id            = subnet
      private_ipv4_address = local.grafana_lb.internal ? local.grafana_lb_addresses[i] : null
      allocation_id        = local.grafana_lb.internal ? null : local.grafana_lb_addresses[i]
    }
  ]

  # Plain http: an NLB terminates nothing. See `grafana_load_balancer`.
  grafana_scheme = "http"

  grafana_load_balancer_address = one(aws_lb.grafana[*].dns_name)

  # The Service stays ClusterIP (the target group registers pods directly), so
  # the only chart value needed is the external URL.
  grafana_load_balancer_values = local.grafana_lb == null || local.grafana_lb.host == null ? [] : [yamlencode({
    grafana = {
      "grafana.ini" = {
        # Share links, alert links, and OAuth redirect URIs are built from this
        # and break silently if it differs from the host users reach.
        server = { root_url = "${local.grafana_scheme}://${local.grafana_lb.host}" }
      }
    }
  })]
}

resource "aws_security_group" "grafana_nlb" {
  count = local.grafana_lb == null ? 0 : 1

  name_prefix = "${var.name_prefix}-mzmon-grafana-"
  description = "Grafana NLB for ${var.name_prefix}"
  vpc_id      = local.grafana_lb.vpc_id

  tags = merge(local.common_tags, { Backend = "grafana" })

  # The NLB holds this group, so destroy-then-create fails. Same as the security
  # group in `aws/modules/database`.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "grafana_nlb" {
  count = local.grafana_lb == null ? 0 : 1

  description       = "Allow egress from the Grafana NLB"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.grafana_nlb[0].id

  tags = merge(local.common_tags, { Backend = "grafana" })
}

# One rule per CIDR: a single rule with a list is recreated on every edit, which
# fails mid-upgrade as a duplicate rule.
# https://github.com/hashicorp/terraform-provider-aws/issues/38526
#
# This is the allowlist. The chart cannot check it (the Service is ClusterIP), so
# the guard is the validation on `grafana_load_balancer`.
resource "aws_vpc_security_group_ingress_rule" "grafana_nlb" {
  for_each = local.grafana_lb == null ? toset([]) : toset(local.grafana_lb.ingress_cidr_blocks)

  description       = "Allow Grafana from ${each.value}"
  from_port         = local.grafana_lb_listener_port
  to_port           = local.grafana_lb_listener_port
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.grafana_nlb[0].id
  cidr_ipv4         = each.value

  tags = merge(local.common_tags, { Backend = "grafana" })
}

resource "aws_lb" "grafana" {
  count = local.grafana_lb == null ? 0 : 1

  name                             = var.grafana_nlb_name
  name_prefix                      = var.grafana_nlb_name == null ? local.grafana_lb_name_prefix : null
  internal                         = local.grafana_lb.internal
  load_balancer_type               = "network"
  subnets                          = length(local.grafana_lb_subnet_mappings) == 0 ? local.grafana_lb.subnet_ids : null
  enable_cross_zone_load_balancing = local.grafana_lb.enable_cross_zone_load_balancing
  security_groups                  = [aws_security_group.grafana_nlb[0].id]

  dynamic "subnet_mapping" {
    for_each = local.grafana_lb_subnet_mappings

    content {
      subnet_id            = subnet_mapping.value.subnet_id
      private_ipv4_address = subnet_mapping.value.private_ipv4_address
      allocation_id        = subnet_mapping.value.allocation_id
    }
  }

  tags = merge(local.common_tags, { Backend = "grafana" })

  # Works because the name is generated. With `grafana_nlb_name` set, the
  # replacement collides with the old load balancer; that is the caller's choice.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "grafana" {
  count = local.grafana_lb == null ? 0 : 1

  name_prefix        = local.grafana_lb_name_prefix
  port               = local.grafana_pod_port
  protocol           = "TCP"
  target_type        = "ip"
  vpc_id             = local.grafana_lb.vpc_id
  preserve_client_ip = true

  health_check {
    enabled  = true
    protocol = "HTTP"
    # Follows the registered target port instead of hardcoding one.
    port                = "traffic-port"
    path                = "/api/health"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, { Backend = "grafana" })

  # The listener forwards to this group, so destroy-then-create fails with
  # ResourceInUse.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "grafana" {
  count = local.grafana_lb == null ? 0 : 1

  load_balancer_arn = aws_lb.grafana[0].arn
  port              = local.grafana_lb_listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana[0].arn
  }

  tags = merge(local.common_tags, { Backend = "grafana" })
}

# With `preserve_client_ip`, data traffic keeps the client's address, so this
# rule is what lets the NLB health checks through. The NLB security group above
# governs client access.
resource "aws_security_group_rule" "grafana_nlb_to_nodes" {
  count = local.grafana_lb == null ? 0 : 1

  type                     = "ingress"
  from_port                = local.grafana_pod_port
  to_port                  = local.grafana_pod_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.grafana_nlb[0].id
  security_group_id        = local.grafana_lb.node_security_group_id
  description              = "Allow Grafana traffic and health checks from the Grafana NLB"
}

# `kubectl_manifest`, not `kubernetes_manifest`, which needs the CRD schema at
# plan time, before the load-balancer controller installs it. Applied after the
# chart, which creates the referenced Service.
resource "kubectl_manifest" "grafana_target_group_binding" {
  count = local.grafana_lb == null ? 0 : 1

  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "mzmon-grafana"
      namespace = var.namespace
    }
    spec = {
      # The chart pins `grafana.fullnameOverride`, so the name is static. The port
      # is the Service's; the controller registers pods on their target port.
      serviceRef = {
        name = "grafana"
        port = var.grafana_service_port
      }
      targetGroupARN = aws_lb_target_group.grafana[0].arn
      targetType     = "ip"
      networking = {
        ingress = [{
          from  = [{ securityGroup = { groupID = aws_security_group.grafana_nlb[0].id } }]
          ports = [{ protocol = "TCP", port = local.grafana_pod_port }]
        }]
      }
    }
  })

  depends_on = [module.monitoring]
}

# ==============================================================================
# Provider metrics: what the gateway pulls
# ==============================================================================
# Named, never discovered: the chart pulls exactly these resources. This module's
# own resources join the caller's unless `include_monitoring_resources` is false.

locals {
  provider_metrics_rds_instances = local.provider_metrics_enabled ? distinct(concat(
    var.provider_metrics.rds_instance_ids,
    var.provider_metrics.include_monitoring_resources && local.create_grafana_database ? [module.grafana_database[0].db_instance_id] : [],
  )) : []

  provider_metrics_s3_buckets = local.provider_metrics_enabled ? distinct(concat(
    var.provider_metrics.s3_bucket_names,
    var.provider_metrics.include_monitoring_resources ? [for k in keys(local.service_accounts) : aws_s3_bucket.telemetry[k].id] : [],
  )) : []

  # Optional fields are omitted rather than set to null, so the chart's own
  # defaults survive.
  provider_metrics_values = local.provider_metrics_enabled ? [yamlencode({
    pipeline = {
      metrics = {
        provider = {
          cloudwatch = merge(
            {
              enabled = true
              region  = var.region
              rds     = { instances = local.provider_metrics_rds_instances }
              s3      = { buckets = local.provider_metrics_s3_buckets }
              eks     = { clusters = distinct(var.provider_metrics.eks_cluster_names) }
            },
            var.provider_metrics.scrape_interval == null ? {} : { scrapeInterval = var.provider_metrics.scrape_interval },
            var.provider_metrics.importance == null ? {} : { metricImportance = var.provider_metrics.importance },
          )
        }
      }
    }
  })] : []
}

# ==============================================================================
# The stack
# ==============================================================================

module "monitoring" {
  # Pinned to a released tag. The module reads its chart version from the chart
  # beside it, so this ref alone sets the chart version.
  #
  # To develop against an unreleased module, use a *relative* path to a local
  # checkout (`../../../../materialize-monitoring/terraform/modules/materialize-monitoring`).
  # An absolute path copies the module without the chart, and sizing profiles break.
  #
  # The `/` in the tag needs Terraform >= 1.10 (hashicorp/terraform#35552).
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.30.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart_version = var.chart_version

  # Null uses the monitoring module's default (they are `nullable = false` there).
  # None can be set through `additional_values`, so they must be forwarded.
  chart_registry         = var.chart_registry
  enable_monitoring_crds = var.enable_monitoring_crds
  install_timeout        = var.install_timeout

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class
  min_zones     = var.min_zones

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

  # In-cluster TLS defaults to on here rather than in the monitoring module: every
  # example in this repo installs cert-manager, other consumers may not.
  certificates_enabled       = var.certificates_enabled
  internal_tls               = coalesce(var.internal_tls, var.certificates_enabled ? "authenticate" : "off")
  issuer_ref                 = var.issuer_ref
  internal_issuer_ref        = var.internal_issuer_ref
  grafana_external_dns_names = var.grafana_external_dns_names
  certificate_duration       = var.certificate_duration
  certificate_renew_before   = var.certificate_renew_before

  # Explicit, not inferred from host/password: those can be unknown at plan time
  # (instance endpoint, generated password), but these conditions are plan-known.
  grafana_database_enabled                = local.create_grafana_database || var.grafana_database_host != null
  grafana_database_manage_password_secret = local.create_grafana_database || var.grafana_database_password != null

  # TODO: pass the Grafana Service port once the monitoring module accepts one.
  # The chart sets it (`grafana.service.port`, 80) and nothing here sets it on the
  # chart, so they agree by coincidence. In-cluster TLS will move that port.
  #
  # grafana_service_port = 80

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
    # Only set when the provider pull is on; the gateway needs no bucket access.
    gateway_service_account_annotations = local.provider_metrics_enabled ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.gateway[0].arn
    } : {}
  }

  # Passed through; the monitoring module validates them and keeps credentials
  # out of the Helm values (they go in the gateway Secret).
  datadog_metrics = var.datadog_metrics
  datadog_api_key = var.datadog_api_key

  otlp_metrics             = var.otlp_metrics
  otlp_auth_header_secrets = var.otlp_auth_header_secrets
  otlp_auth_bearer_token   = var.otlp_auth_bearer_token

  # Passed through; the monitoring module validates them and fails the plan when
  # a receiver reads a key `alerting_receiver_secrets` does not set.
  alert_rules               = var.alert_rules
  alerting                  = var.alerting
  alerting_receiver_secrets = var.alerting_receiver_secrets
  alertmanager_namespace    = var.alertmanager_namespace

  # Computed values first, so `additional_values` overrides them.
  additional_values = concat(
    local.grafana_load_balancer_values,
    local.provider_metrics_values,
    var.additional_values,
  )

  depends_on = [
    aws_iam_role_policy.telemetry,
    aws_iam_role_policy.gateway,
    aws_s3_bucket_public_access_block.telemetry,
  ]
}
