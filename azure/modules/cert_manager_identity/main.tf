locals {
  dns_zone_rg = coalesce(var.dns_zone_resource_group, var.resource_group_name)
}

resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "${var.prefix}-cert-manager"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  name                = "${var.prefix}-cert-manager"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.cert_manager.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.cert_manager_namespace}:${var.cert_manager_service_account_name}"
}

data "azurerm_dns_zone" "zone" {
  name                = var.dns_zone_name
  resource_group_name = local.dns_zone_rg
}

resource "azurerm_role_assignment" "cert_manager_dns" {
  scope                = data.azurerm_dns_zone.zone.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
}
