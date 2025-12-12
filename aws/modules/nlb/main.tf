locals {
  # AWS load balancer name_prefix has a maximum length of 6 characters
  # We trim the name_prefix to ensure it fits within this limit
  trimmed_name_prefix = substr(var.name_prefix, 0, min(6, length(var.name_prefix)))
}

resource "aws_security_group" "nlb" {
  name_prefix = "${local.trimmed_name_prefix}-nlb-sg"
  description = "Security group for ${var.name_prefix} NLB"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

# Create separate ingress rules to avoid duplicate rule errors during upgrades
# https://github.com/hashicorp/terraform-provider-aws/issues/38526
resource "aws_vpc_security_group_ingress_rule" "nlb_pgwire" {
  for_each          = toset(var.ingress_cidr_blocks)
  description       = "Allow Materialize pgwire from ${each.value}"
  from_port         = 6875
  to_port           = 6875
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = each.value

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http" {
  for_each          = toset(var.ingress_cidr_blocks)
  description       = "Allow Materialize HTTP from ${each.value}"
  from_port         = 6876
  to_port           = 6876
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = each.value

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "nlb_console" {
  for_each          = toset(var.ingress_cidr_blocks)
  description       = "Allow Materialize Console/Health from ${each.value}"
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = each.value

  tags = var.tags
}

resource "aws_lb" "nlb" {
  name_prefix                      = local.trimmed_name_prefix
  internal                         = var.internal
  load_balancer_type               = "network"
  subnets                          = var.subnet_ids
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  security_groups                  = [aws_security_group.nlb.id]
  tags                             = var.tags

  # Adding security_groups to an existing NLB requires recreation
  # This is expected behavior when migrating from non-SG to SG-enabled NLB
  lifecycle {
    create_before_destroy = true
  }
}

module "target_pgwire" {
  source = "./target"

  name               = "${var.name_prefix}-pgwire"
  nlb_arn            = aws_lb.nlb.arn
  namespace          = var.namespace
  vpc_id             = var.vpc_id
  preserve_client_ip = true
  port               = 6875
  service_name       = "mz${var.mz_resource_id}-balancerd"
  health_check_path  = "/api/readyz"
  tags               = var.tags
}

module "target_http" {
  source = "./target"

  name               = "${var.name_prefix}-http"
  nlb_arn            = aws_lb.nlb.arn
  namespace          = var.namespace
  vpc_id             = var.vpc_id
  preserve_client_ip = true
  port               = 6876
  service_name       = "mz${var.mz_resource_id}-balancerd"
  health_check_path  = "/api/readyz"
  tags               = var.tags
}

module "target_console" {
  source = "./target"

  name               = "${var.name_prefix}-console"
  nlb_arn            = aws_lb.nlb.arn
  namespace          = var.namespace
  vpc_id             = var.vpc_id
  preserve_client_ip = true
  port               = 8080
  service_name       = "mz${var.mz_resource_id}-console"
  health_check_path  = "/"
  tags               = var.tags
}

# Allow traffic from NLB Security Group to EKS Node Security Group
resource "aws_security_group_rule" "allow_nlb_to_nodes_pgwire" {
  type                     = "ingress"
  from_port                = 6875
  to_port                  = 6875
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb.id
  security_group_id        = var.node_security_group_id
  description              = "Allow pgwire from NLB SG"
}

resource "aws_security_group_rule" "allow_nlb_to_nodes_http" {
  type                     = "ingress"
  from_port                = 6876
  to_port                  = 6876
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb.id
  security_group_id        = var.node_security_group_id
  description              = "Allow HTTP from NLB SG"
}

resource "aws_security_group_rule" "allow_nlb_to_nodes_health" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb.id
  security_group_id        = var.node_security_group_id
  description              = "Allow Health Checks from NLB SG"
}
