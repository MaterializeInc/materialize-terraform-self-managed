locals {
  zone_domain = lower(trimsuffix(data.azurerm_dns_zone.this.name, "."))
  stem_domain = var.stem_domain != null ? lower(trimsuffix(var.stem_domain, ".")) : local.zone_domain

  fqdns = {
    for key, entry in var.subdomains :
    key => coalesce(entry.subdomain, key) == "@" ? local.stem_domain : "${coalesce(entry.subdomain, key)}.${local.stem_domain}"
  }

  # Azure DNS names a record relative to its zone, with "@" for the apex.
  record_sets = {
    for key, entry in var.subdomains : key => merge(entry, {
      fqdn   = local.fqdns[key]
      values = lookup(var.records, key, [])
      name   = local.fqdns[key] == local.zone_domain ? "@" : trimsuffix(local.fqdns[key], ".${local.zone_domain}")
    }) if entry.create
  }

  cert_manager_dns01 = var.cert_manager_dns01 != null

  # /subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.Network/dnsZones/<zone>
  zone_subscription_id = split("/", data.azurerm_dns_zone.this.id)[2]
}

# The zone is looked up, never managed: records are added to a zone that
# already exists, and nothing here can delete it.
data "azurerm_dns_zone" "this" {
  name                = var.zone_name
  resource_group_name = var.zone_resource_group_name

  lifecycle {
    postcondition {
      condition = (
        var.stem_domain == null ||
        lower(trimsuffix(var.stem_domain, ".")) == lower(self.name) ||
        endswith(lower(trimsuffix(var.stem_domain, ".")), ".${lower(self.name)}")
      )
      error_message = "stem_domain must be the DNS zone's domain or a name inside it."
    }
  }
}

resource "azurerm_dns_a_record" "subdomains" {
  for_each = { for key, entry in local.record_sets : key => entry if entry.type == "A" }

  name                = each.value.name
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = var.zone_resource_group_name
  ttl                 = each.value.ttl
  records             = each.value.values
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = each.value.type == "CNAME" ? length(each.value.values) == 1 : length(each.value.values) > 0
      error_message = "${each.key}: create = true needs records[\"${each.key}\"], with one target for a CNAME or at least one address for A and AAAA."
    }
  }
}

resource "azurerm_dns_aaaa_record" "subdomains" {
  for_each = { for key, entry in local.record_sets : key => entry if entry.type == "AAAA" }

  name                = each.value.name
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = var.zone_resource_group_name
  ttl                 = each.value.ttl
  records             = each.value.values
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = each.value.type == "CNAME" ? length(each.value.values) == 1 : length(each.value.values) > 0
      error_message = "${each.key}: create = true needs records[\"${each.key}\"], with one target for a CNAME or at least one address for A and AAAA."
    }
  }
}

resource "azurerm_dns_cname_record" "subdomains" {
  for_each = { for key, entry in local.record_sets : key => entry if entry.type == "CNAME" }

  name                = each.value.name
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = var.zone_resource_group_name
  ttl                 = each.value.ttl
  record              = one(each.value.values)
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = each.value.type == "CNAME" ? length(each.value.values) == 1 : length(each.value.values) > 0
      error_message = "${each.key}: create = true needs records[\"${each.key}\"], with one target for a CNAME or at least one address for A and AAAA."
    }
    precondition {
      condition     = each.value.name != "@"
      error_message = "${each.key}: a CNAME cannot sit at the zone's apex, ${local.zone_domain}."
    }
  }
}

# cert-manager's DNS-01 identity: a user-assigned managed identity that may
# change records in this zone only, which cert-manager's Kubernetes service
# account acts as through Azure Workload Identity.
resource "azurerm_user_assigned_identity" "cert_manager" {
  count = local.cert_manager_dns01 ? 1 : 0

  name                = "${var.prefix}-cert-manager-dns01"
  location            = var.cert_manager_dns01.location
  resource_group_name = var.cert_manager_dns01.resource_group_name
  tags                = var.tags
}

# Establishes trust between cert-manager's ServiceAccount and the identity. The
# audience is fixed by Entra's token-exchange endpoint.
resource "azurerm_federated_identity_credential" "cert_manager" {
  count = local.cert_manager_dns01 ? 1 : 0

  name                      = "${var.prefix}-cert-manager-dns01"
  user_assigned_identity_id = azurerm_user_assigned_identity.cert_manager[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.cert_manager_dns01.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.cert_manager_dns01.namespace}:${var.cert_manager_dns01.service_account_name}"
}

resource "azurerm_role_assignment" "cert_manager" {
  count = local.cert_manager_dns01 ? 1 : 0

  scope                = data.azurerm_dns_zone.this.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager[0].principal_id
  principal_type       = "ServicePrincipal"
}
