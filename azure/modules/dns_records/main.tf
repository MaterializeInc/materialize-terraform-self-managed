data "azurerm_dns_zone" "zone" {
  name                = var.dns_zone_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_dns_a_record" "balancerd" {
  name                = var.balancerd_domain_name
  zone_name           = data.azurerm_dns_zone.zone.name
  resource_group_name = var.resource_group_name
  ttl                 = var.ttl
  records             = [var.balancerd_ip]
  tags                = var.tags
}

resource "azurerm_dns_a_record" "console" {
  name                = var.console_domain_name
  zone_name           = data.azurerm_dns_zone.zone.name
  resource_group_name = var.resource_group_name
  ttl                 = var.ttl
  records             = [var.console_ip]
  tags                = var.tags
}
