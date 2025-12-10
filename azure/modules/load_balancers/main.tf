# Network Security Group for AKS subnet allows traffic from loadbalancer and traffic from Internet
# https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-troubleshoot#problem-no-inbound-connectivity-to-standard-external-load-balancers
# https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview#allowazureloadbalancerinbound
resource "azurerm_network_security_group" "aks" {
  count               = var.internal ? 0 : 1
  name                = "${var.prefix}-public-lb-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "public_lb_ingress" {
  count                   = var.internal ? 0 : 1
  name                    = "AllowPublicLBIngress"
  priority                = 104
  direction               = "Inbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_address_prefixes = var.ingress_cidr_blocks
  source_port_range       = "*"
  #TODO: Making this more specific by adding the AKS subnet/VNet CIDR considering that as destination address prefix
  # didn't work,  figure out why.
  destination_address_prefix  = "*"
  destination_port_ranges     = ["6875", "6876", "8080"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks[0].name
}

resource "azurerm_subnet_network_security_group_association" "subnet_sg_association" {
  count                     = var.internal ? 0 : 1
  subnet_id                 = var.aks_subnet_id
  network_security_group_id = azurerm_network_security_group.aks[0].id
}

resource "kubernetes_service" "console_load_balancer" {
  metadata {
    name      = "mz${var.resource_id}-console-lb"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = var.internal ? "true" : "false"
    }
  }

  spec {
    type                        = "LoadBalancer"
    external_traffic_policy     = "Local"
    load_balancer_source_ranges = var.internal ? null : var.ingress_cidr_blocks
    selector = {
      "materialize.cloud/name" = "mz${var.resource_id}-console"
    }
    port {
      name        = "http"
      port        = var.materialize_console_port
      target_port = 8080
      protocol    = "TCP"
    }
  }

  wait_for_load_balancer = true

  lifecycle {
    ignore_changes = [
      # The resource_id is known only after apply,
      # so terraform wants to destroy the resource
      # on any changes to the Materialize CR.
      metadata[0].name,
      spec[0].selector["materialize.cloud/name"],
    ]
  }
}

resource "kubernetes_service" "balancerd_load_balancer" {
  metadata {
    name      = "mz${var.resource_id}-balancerd-lb"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = var.internal ? "true" : "false"
    }
  }

  spec {
    type                        = "LoadBalancer"
    external_traffic_policy     = "Local"
    load_balancer_source_ranges = var.internal ? null : var.ingress_cidr_blocks
    selector = {
      "materialize.cloud/name" = "mz${var.resource_id}-balancerd"
    }
    port {
      name        = "sql"
      port        = var.materialize_balancerd_sql_port
      target_port = 6875
      protocol    = "TCP"
    }
    port {
      name        = "https"
      port        = var.materialize_balancerd_https_port
      target_port = 6876
      protocol    = "TCP"
    }
  }

  wait_for_load_balancer = true

  lifecycle {
    ignore_changes = [
      # The resource_id is known only after apply,
      # so terraform wants to destroy the resource
      # on any changes to the Materialize CR.
      metadata[0].name,
      spec[0].selector["materialize.cloud/name"],
    ]
  }
}
