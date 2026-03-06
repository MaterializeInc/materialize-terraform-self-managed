locals {
  # AWS load balancer name_prefix has a maximum length of 6 characters
  # We trim the name_prefix to ensure it fits within this limit
  trimmed_name_prefix = substr(var.name_prefix, 0, min(6, length(var.name_prefix)))
}

resource "aws_security_group" "nlb" {
  count = var.create_security_group ? 1 : 0

  name_prefix = "${local.trimmed_name_prefix}-nlb-sg"
  description = "Security group for ${var.name_prefix} NLB"
  vpc_id      = var.vpc_id
  tags        = var.tags
}


# no need to specify from_port and to_port when using -1 for ip_protocol
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule#ip_protocol-1
resource "aws_vpc_security_group_egress_rule" "nlb_egress" {
  count = var.create_security_group ? 1 : 0

  description       = "Allow egress traffic from the NLB Security Group"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.nlb[0].id
  tags              = var.tags
}

# Create separate ingress rules to avoid duplicate rule errors during upgrades
# https://github.com/hashicorp/terraform-provider-aws/issues/38526
resource "aws_vpc_security_group_ingress_rule" "nlb_pgwire" {
  for_each          = var.create_security_group ? toset(var.ingress_cidr_blocks) : toset([])
  description       = "Allow Materialize pgwire from ${each.value}"
  from_port         = 6875
  to_port           = 6875
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.nlb[0].id
  cidr_ipv4         = each.value

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http" {
  for_each          = var.create_security_group ? toset(var.ingress_cidr_blocks) : toset([])
  description       = "Allow Materialize HTTP from ${each.value}"
  from_port         = 6876
  to_port           = 6876
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.nlb[0].id
  cidr_ipv4         = each.value

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "nlb_console" {
  for_each          = var.create_security_group ? toset(var.ingress_cidr_blocks) : toset([])
  description       = "Allow Materialize Console/Health from ${each.value}"
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.nlb[0].id
  cidr_ipv4         = each.value

  tags = var.tags
}

resource "aws_lb" "nlb" {
  name                             = var.nlb_name
  name_prefix                      = var.nlb_name == null ? local.trimmed_name_prefix : null
  internal                         = var.internal
  load_balancer_type               = "network"
  subnets                          = var.subnet_ids
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  security_groups                  = var.create_security_group ? [aws_security_group.nlb[0].id] : null
  tags                             = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

module "target_pgwire" {
  source = "./target"

  name               = "${var.name_prefix}-${var.instance_name}-pgwire"
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

  name               = "${var.name_prefix}-${var.instance_name}-http"
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

  name               = "${var.name_prefix}-${var.instance_name}-console"
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
  count = var.create_security_group ? 1 : 0

  type                     = "ingress"
  from_port                = 6875
  to_port                  = 6875
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb[0].id
  security_group_id        = var.node_security_group_id
  description              = "Allow pgwire from NLB SG"
}

resource "aws_security_group_rule" "allow_nlb_to_nodes_http" {
  count = var.create_security_group ? 1 : 0

  type                     = "ingress"
  from_port                = 6876
  to_port                  = 6876
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb[0].id
  security_group_id        = var.node_security_group_id
  description              = "Allow HTTP from NLB SG"
}

resource "aws_security_group_rule" "allow_nlb_to_nodes_health" {
  count = var.create_security_group ? 1 : 0

  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb[0].id
  security_group_id        = var.node_security_group_id
  description              = "Allow Health Checks from NLB SG"
}
