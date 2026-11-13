locals {
  zone_domain = trimsuffix(data.aws_route53_zone.this.name, ".")
  stem_domain = var.stem_domain != null ? lower(trimsuffix(var.stem_domain, ".")) : local.zone_domain

  fqdns = {
    for key, entry in var.subdomains :
    key => coalesce(entry.subdomain, key) == "@" ? local.stem_domain : "${coalesce(entry.subdomain, key)}.${local.stem_domain}"
  }

  record_sets = {
    for key, entry in var.subdomains : key => merge(entry, { fqdn = local.fqdns[key], values = lookup(var.records, key, []) }) if entry.create
  }

  cert_manager_dns01 = var.cert_manager_dns01 != null
  oidc_issuer_host   = local.cert_manager_dns01 ? trimprefix(var.cert_manager_dns01.cluster_oidc_issuer_url, "https://") : null
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

# The zone is looked up, never managed: records are added to a zone that
# already exists, and nothing here can delete it.
data "aws_route53_zone" "this" {
  zone_id = var.zone_id

  lifecycle {
    postcondition {
      # A conditional rather than ||: Terraform before 1.12 evaluates both sides
      # of ||, so a null stem_domain would still reach trimsuffix.
      condition = var.stem_domain == null ? true : (
        lower(trimsuffix(var.stem_domain, ".")) == trimsuffix(self.name, ".") ||
        endswith(lower(trimsuffix(var.stem_domain, ".")), ".${trimsuffix(self.name, ".")}")
      )
      error_message = "stem_domain must be the hosted zone's domain or a name inside it."
    }
  }
}

resource "aws_route53_record" "subdomains" {
  for_each = local.record_sets

  zone_id = var.zone_id
  name    = each.value.fqdn
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values

  lifecycle {
    precondition {
      condition     = each.value.type == "CNAME" ? length(each.value.values) == 1 : length(each.value.values) > 0
      error_message = "${each.key}: create = true needs records[\"${each.key}\"], with one target for a CNAME or at least one address for A and AAAA."
    }
    precondition {
      condition     = !(each.value.type == "CNAME" && each.value.fqdn == local.zone_domain)
      error_message = "${each.key}: a CNAME cannot sit at the zone's apex, ${local.zone_domain}."
    }
  }
}

# cert-manager's DNS-01 identity: an IAM role its Kubernetes service account
# assumes through IRSA, which may only write the TXT records ACME challenges
# use for names under stem_domain.
resource "aws_iam_role" "cert_manager" {
  count = local.cert_manager_dns01 ? 1 : 0

  name                 = "${var.name_prefix}-cert-manager-dns01"
  permissions_boundary = var.iam_permissions_boundary

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.cert_manager_dns01.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_host}:sub" = "system:serviceaccount:${var.cert_manager_dns01.namespace}:${var.cert_manager_dns01.service_account_name}"
            "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cert_manager" {
  count = local.cert_manager_dns01 ? 1 : 0

  name = "route53-dns01"
  role = aws_iam_role.cert_manager[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "route53:GetChange"
        Resource = "arn:${data.aws_partition.current.partition}:route53:::change/*"
      },
      {
        Effect   = "Allow"
        Action   = "route53:ListResourceRecordSets"
        Resource = data.aws_route53_zone.this.arn
      },
      {
        Effect   = "Allow"
        Action   = "route53:ChangeResourceRecordSets"
        Resource = data.aws_route53_zone.this.arn
        Condition = {
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsRecordTypes" = ["TXT"]
          }
          "ForAllValues:StringLike" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = [
              "_acme-challenge.${local.stem_domain}",
              "_acme-challenge.*.${local.stem_domain}",
            ]
          }
        }
      }
    ]
  })
}
