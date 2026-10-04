
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

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

  # Adopt and tag the default network ACL. The BYOC permissions boundary only
  # allows `ec2:Delete*` and `ec2:*NetworkAclEntry` on tagged resources, so an
  # untagged ACL makes destroy fail with UnauthorizedOperation.
  manage_default_network_acl = true

  # needed for EKS Cluster private endpoint
  # https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html#cluster-endpoint-private
  enable_dhcp_options              = true
  dhcp_options_domain_name_servers = ["AmazonProvidedDNS"]

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
  version = "~> 6.0"

  create = var.enable_vpc_endpoints

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = var.enable_vpc_endpoints ? [aws_security_group.vpc_endpoints[0].id] : []

  endpoints = {
    # Persist blob storage is in S3, so keep that traffic in the VPC.
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "${var.name_prefix}-s3-gateway-endpoint" }
    }

    # No RDS endpoint: pods reach RDS by private IP inside the VPC, so it would
    # only add cost (https://aws.amazon.com/privatelink/pricing/).

    # Used by Karpenter.
    ec2 = {
      service             = "ec2"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ec2-endpoint" }
    }

    # TODO: likely unneeded since we use k8s secrets; discuss and remove.
    secretsmanager = {
      service             = "secretsmanager"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-secretsmanager-endpoint" }
    }

    # ssm, ssmmessages and ec2messages enable Session Manager access to nodes.
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

    # Used by IRSA.
    sts = {
      service             = "sts"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-sts-endpoint" }
    }

    # TODO: likely unneeded since nodes rely on EBS encryption; discuss and remove.
    kms = {
      service             = "kms"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-kms-endpoint" }
    }

    # Used by aws-lbc to manage load balancers.
    elasticloadbalancing = {
      service             = "elasticloadbalancing"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-elasticloadbalancing-endpoint" }
    }

    # Image pulls from ECR.
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ecr-api-endpoint" }
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ecr-dkr-endpoint" }
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
