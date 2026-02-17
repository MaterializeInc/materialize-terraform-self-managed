# =============================================================================
# Migration Reference Outputs
# =============================================================================

# Networking
output "networking" {
  description = "Networking details"
  value = {
    vpc_id             = module.networking.vpc_id
    private_subnet_ids = module.networking.private_subnet_ids
    public_subnet_ids  = module.networking.public_subnet_ids
  }
}

# EKS Cluster
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster communication"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_issuer_url" {
  description = "The URL for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

# Database
output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = module.database.db_instance_endpoint
}

output "database_name" {
  description = "RDS database name"
  value       = module.database.db_instance_name
}

output "database_username" {
  description = "RDS instance username"
  value       = module.database.db_instance_username
  sensitive   = true
}

# Storage
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.storage.bucket_name
}

output "materialize_s3_role_arn" {
  description = "The ARN of the IAM role for Materialize S3 access"
  value       = module.storage.materialize_s3_role_arn
}

# Operator
output "operator" {
  description = "Materialize operator details"
  value = {
    namespace      = module.operator.operator_namespace
    release_name   = module.operator.operator_release_name
    release_status = module.operator.operator_release_status
  }
}

# Materialize Instance
output "materialize_instance_name" {
  description = "Materialize instance name"
  value       = local.materialize_instance_name
}

output "materialize_instance_namespace" {
  description = "Materialize instance namespace"
  value       = local.materialize_instance_namespace
}

output "materialize_instance_resource_id" {
  description = "Materialize instance resource ID"
  value       = data.kubernetes_resource.materialize_instances[local.materialize_instance_name].object.status.resourceId
}

output "materialize_instance_metadata_backend_url" {
  description = "Materialize instance metadata backend URL"
  value       = local.metadata_backend_url
  sensitive   = true
}

output "materialize_instance_persist_backend_url" {
  description = "Materialize instance persist backend URL"
  value       = local.persist_backend_url
  sensitive   = true
}

# Load Balancer
output "nlb_arn" {
  description = "ARN of the Materialize NLB"
  value       = module.nlb[local.materialize_instance_name].nlb_arn
}

output "nlb_dns_name" {
  description = "DNS name of the Materialize NLB"
  value       = module.nlb[local.materialize_instance_name].nlb_dns_name
}

output "external_login_password_mz_system" {
  description = "Password for external login to Materialize"
  value       = random_password.external_login_password_mz_system.result
  sensitive   = true
}
