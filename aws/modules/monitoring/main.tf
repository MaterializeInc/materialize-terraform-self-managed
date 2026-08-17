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
# The NLB, its listener, its target group, and the TargetGroupBinding that links
# them to the Grafana Service, all as Terraform resources. Copied from
# `aws/modules/nlb` rather than imported: that module is keyed on a Materialize
# instance's `resource_id`, so depending on it would make monitoring wait for
# Materialize to be fully stood up.
#
# Not `service.type: LoadBalancer` with AWS annotations: letting the
# load-balancer controller build the NLB leaves its address discoverable only by
# reading the Service back after apply, which races the controller, and pushes
# every setting through an annotation string with no type checking.

locals {
  grafana_lb = var.grafana_load_balancer
  # `name_prefix` on an ELB is capped at 6 characters.
  grafana_lb_name_prefix = substr(var.name_prefix, 0, min(6, length(var.name_prefix)))

  # Grafana's container port. The chart's Service is 80 -> 3000; the target group
  # registers pod IPs, so it is the container port that matters here.
  grafana_pod_port = 3000

  grafana_lb_listener_port = try(local.grafana_lb.listener_port, 80)

  # Pre-allocated addresses become `subnet_mapping` blocks, which are mutually
  # exclusive with `subnets` — hence the null when none were supplied.
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

  # The Service stays ClusterIP — the target group registers pods directly — so
  # the only chart value the load balancer implies is the external URL.
  grafana_load_balancer_values = local.grafana_lb == null || local.grafana_lb.host == null ? [] : [yamlencode({
    grafana = {
      "grafana.ini" = {
        # Grafana builds share links, alert notification links, and OAuth redirect
        # URIs from this. All three break silently when it disagrees with the host
        # users actually reach.
        server = { root_url = "${local.grafana_scheme}://${local.grafana_lb.host}" }
      }
    }
  })]
}

resource "aws_security_group" "grafana_nlb" {
  count = local.grafana_lb == null ? 0 : 1

  name_prefix = "${local.grafana_lb_name_prefix}-mzmon-gf-"
  description = "Grafana NLB for ${var.name_prefix}"
  vpc_id      = local.grafana_lb.vpc_id

  tags = merge(local.common_tags, { Backend = "grafana" })
}

resource "aws_vpc_security_group_egress_rule" "grafana_nlb" {
  count = local.grafana_lb == null ? 0 : 1

  description       = "Allow egress from the Grafana NLB"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.grafana_nlb[0].id

  tags = merge(local.common_tags, { Backend = "grafana" })
}

# One rule per CIDR rather than one rule with a list: a single rule with a
# changing list is destroyed and recreated on every edit, which the provider
# reports as a duplicate-rule error mid-upgrade.
# https://github.com/hashicorp/terraform-provider-aws/issues/38526
#
# This is the allowlist. The Service is ClusterIP, so there is no
# `loadBalancerSourceRanges` for the chart to check — the guard is the validation
# on `grafana_load_balancer`.
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

  name_prefix                      = "${local.grafana_lb_name_prefix}-"
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

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "grafana" {
  count = local.grafana_lb == null ? 0 : 1

  name_prefix        = "${local.grafana_lb_name_prefix}-"
  port               = local.grafana_pod_port
  protocol           = "TCP"
  target_type        = "ip"
  vpc_id             = local.grafana_lb.vpc_id
  preserve_client_ip = true

  health_check {
    enabled  = true
    protocol = "HTTP"
    # Follows whatever port a target is registered on, rather than hardcoding one
    # that only happens to match today.
    port                = "traffic-port"
    path                = "/api/health"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, { Backend = "grafana" })

  # The listener forwards to this group, so a destroy-then-create replacement
  # fails with ResourceInUse. Create the replacement first, let the listener and
  # the TargetGroupBinding repoint, then drop the old group.
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

# With `preserve_client_ip`, data traffic reaches the pod with the client's own
# address, so this rule is what lets the NLB's health checks through. Client
# access itself is governed by the NLB security group above.
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

# `kubectl_manifest` rather than `kubernetes_manifest`: the CRD is installed by
# the load-balancer controller, and `kubernetes_manifest` looks a schema up at
# plan time, so it fails before the CRD exists.
#
# Applied after the chart, because the Service it references has to exist first.
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
      # is the Service's own, not the container's — the controller resolves the
      # Service's endpoints from it and registers pods on their target port.
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
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.17.0"

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

  # TODO: pass the Grafana Service port through, once the monitoring module takes
  # one. Today the chart decides it (`grafana.service.port`, 80) and nothing here
  # states it, so the two agree only by coincidence.
  #
  # This becomes load-bearing with in-cluster TLS: Grafana stops serving plain
  # HTTP, the Service port moves with it, and anything still assuming 80 points at
  # a port that is no longer there. Deliberately not wired yet — it needs a
  # variable on the monitoring module and a matching chart value, which is a
  # change of its own.
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
  }

  # Straight pass-through; the monitoring module validates the tiers, the OTLP
  # protocol, and the url-has-no-scheme rule, and rejects a bearer token combined
  # with headers. Credentials never enter the Helm values — that module puts them
  # in the gateway Secret and rolls the gateway when one changes.
  datadog_metrics = var.datadog_metrics
  datadog_api_key = var.datadog_api_key

  otlp_metrics             = var.otlp_metrics
  otlp_auth_header_secrets = var.otlp_auth_header_secrets
  otlp_auth_bearer_token   = var.otlp_auth_bearer_token

  # Ingress values ahead of the caller's, so `additional_values` still overrides
  # anything computed here.
  additional_values = concat(local.grafana_load_balancer_values, var.additional_values)

  depends_on = [
    aws_iam_role_policy.telemetry,
    aws_s3_bucket_public_access_block.telemetry,
  ]
}
