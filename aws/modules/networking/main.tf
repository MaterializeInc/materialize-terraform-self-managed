
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  create_vpc = var.create_vpc

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for EKS
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = "1"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb"                       = "1"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
  }

  tags = var.tags

}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"

  create = var.enable_vpc_endpoints

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]

  endpoints = {
    ec2 = {
      service             = "ec2"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ec2-endpoint" }
    }
    secretsmanager = {
      service             = "secretsmanager"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-secretsmanager-endpoint" }
    }
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ssm-endpoint" }
    }
    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ssmmessages-endpoint" }
    }
    ec2messages = {
      service             = "ec2messages"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ec2messages-endpoint" }
    }
    sts = {
      service             = "sts"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-sts-endpoint" }
    }
    kms = {
      service             = "kms"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-kms-endpoint" }
    }
    elasticloadbalancing = {
      service             = "elasticloadbalancing"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-elasticloadbalancing-endpoint" }
    }
  }

  tags = var.tags
}

resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = "${var.name_prefix}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = var.tags
}
