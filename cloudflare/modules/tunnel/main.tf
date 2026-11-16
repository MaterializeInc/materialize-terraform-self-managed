/**
 * # Cloudflare Tunnel ingress
 *
 * Exposes a Materialize environment's console and pgwire through a Cloudflare
 * Tunnel, with Cloudflare Access in front of both. The environment keeps
 * internal load balancers only; `cloudflared` connectors running next to it
 * (for example `gcp/modules/cloudflared-connector`) carry the traffic.
 *
 * - The console is served over HTTPS at `console_hostname`.
 * - pgwire, when `sql_hostname` is set, is reached with
 *   `cloudflared access tcp --hostname <sql_hostname> --url localhost:<port>`.
 * - Access allows `access_email_domains` and `access_emails` through the
 *   identity providers in `allowed_idps`, plus the email one-time PIN with
 *   `enable_one_time_pin`. Machine clients use a service token
 *   (`create_service_token`).
 *
 * The hostnames must be in a zone in the same Cloudflare account as the
 * tunnel: Cloudflare only routes `cfargotunnel.com` CNAMEs within one account.
 * The zone's edge certificate must also cover them; on Universal SSL that
 * means one label under the apex.
 */

locals {
  expose_sql = var.sql_hostname != null

  hostnames = merge(
    { console = var.console_hostname },
    local.expose_sql ? { sql = var.sql_hostname } : {},
  )

  allowed_idps = concat(
    var.enable_one_time_pin ? [cloudflare_zero_trust_access_identity_provider.otp[0].id] : [],
    var.allowed_idps,
  )

  access_include = concat(
    [for d in var.access_email_domains : { email_domain = { domain = d } }],
    [for e in var.access_emails : { email = { email = e } }],
  )
}

resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  count = var.enable_one_time_pin ? 1 : 0

  account_id = var.account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.account_id
  name       = var.name
  # Ingress rules live in Cloudflare (the config resource below), so
  # connectors only need the tunnel token.
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = concat(
      [{
        hostname = var.console_hostname
        service  = var.console_origin
        origin_request = {
          no_tls_verify = var.origin_no_tls_verify
        }
      }],
      local.expose_sql ? [{
        hostname = var.sql_hostname
        service  = var.sql_origin
      }] : [],
      # cloudflared requires a catch-all rule last.
      [{ service = "http_status:404" }],
    )
  }

  lifecycle {
    precondition {
      condition     = !local.expose_sql || var.sql_origin != null
      error_message = "sql_origin is required when sql_hostname is set."
    }
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = local.hostnames

  zone_id = var.zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Materialize ${each.key} via tunnel ${var.name}"
}

resource "cloudflare_zero_trust_access_policy" "this" {
  account_id = var.account_id
  name       = "${var.name}-allow"
  decision   = "allow"
  include    = local.access_include

  lifecycle {
    precondition {
      condition     = length(local.access_include) > 0
      error_message = "Set access_email_domains or access_emails; an Access policy with no include rules allows no one."
    }
  }
}

resource "cloudflare_zero_trust_access_service_token" "this" {
  count = var.create_service_token ? 1 : 0

  account_id = var.account_id
  name       = "${var.name}-machine"
  duration   = var.service_token_duration
}

# Service tokens match only a non_identity policy: there is no user for
# Access to look up.
resource "cloudflare_zero_trust_access_policy" "service_token" {
  count = var.create_service_token ? 1 : 0

  account_id = var.account_id
  name       = "${var.name}-machine"
  decision   = "non_identity"
  include = [{
    service_token = { token_id = cloudflare_zero_trust_access_service_token.this[0].id }
  }]
}

resource "cloudflare_zero_trust_access_application" "this" {
  for_each = local.hostnames

  account_id       = var.account_id
  name             = "${var.name}-${each.key}"
  type             = "self_hosted"
  domain           = each.value
  session_duration = var.session_duration
  allowed_idps     = length(local.allowed_idps) > 0 ? local.allowed_idps : null

  policies = concat(
    [{
      id         = cloudflare_zero_trust_access_policy.this.id
      precedence = 1
    }],
    var.create_service_token ? [{
      id         = cloudflare_zero_trust_access_policy.service_token[0].id
      precedence = 2
    }] : [],
  )
}
