locals {
  service_account_name = "aws-node"
  namespace            = "kube-system"
}

# Annotate existing VPC CNI resources for Helm adoption
# EKS creates these resources by default, and Helm needs ownership annotations to manage them
resource "terraform_data" "annotate_existing_resources" {
  count = var.adopt_existing_resources ? 1 : 0

  input = {
    ROLE_ARN        = aws_iam_role.vpc_cni.arn
    KUBECONFIG_DATA = var.kubeconfig_data
  }

  provisioner "local-exec" {
    environment = self.input
    command     = "sh '${path.module}/scripts/annotate-for-helm-adoption.sh'"
  }
}

# IAM role for VPC CNI with OIDC trust
resource "aws_iam_role" "vpc_cni" {
  name                 = "${var.name_prefix}-vpc-cni"
  permissions_boundary = var.iam_permissions_boundary
  tags                 = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${trimprefix(var.oidc_issuer_url, "https://")}:sub" = "system:serviceaccount:${local.namespace}:${local.service_account_name}"
            "${trimprefix(var.oidc_issuer_url, "https://")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Attach AWS managed policy for VPC CNI
resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Helm release for VPC CNI
resource "helm_release" "vpc_cni" {
  name       = "aws-vpc-cni"
  chart      = "aws-vpc-cni"
  repository = "https://aws.github.io/eks-charts"
  version    = var.chart_version
  namespace  = local.namespace

  # Use existing service account (annotated by terraform_data.annotate_existing_resources)
  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = local.service_account_name
  }

  # Network Policy configuration
  set {
    name  = "enableNetworkPolicy"
    value = tostring(var.enable_network_policy)
  }

  dynamic "set" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      name  = "nodeAgent.enablePolicyEventLogs"
      value = tostring(var.enable_policy_event_logs)
    }
  }

  # https://github.com/aws/amazon-vpc-cni-k8s#cni-configuration-variables
  # Prefix delegation settings
  dynamic "set" {
    for_each = var.enable_prefix_delegation ? [1] : []
    content {
      name  = "env.ENABLE_PREFIX_DELEGATION"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = var.enable_prefix_delegation ? [1] : []
    content {
      name  = "env.WARM_PREFIX_TARGET"
      value = tostring(var.warm_prefix_target)
    }
  }

  # IP management settings
  dynamic "set" {
    for_each = var.minimum_ip_target != null ? [1] : []
    content {
      name  = "env.MINIMUM_IP_TARGET"
      value = tostring(var.minimum_ip_target)
    }
  }

  dynamic "set" {
    for_each = var.warm_ip_target != null ? [1] : []
    content {
      name  = "env.WARM_IP_TARGET"
      value = tostring(var.warm_ip_target)
    }
  }

  set {
    name  = "originalMatchLabels"
    value = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.vpc_cni,
    terraform_data.annotate_existing_resources
  ]
}
