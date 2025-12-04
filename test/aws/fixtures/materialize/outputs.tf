# =============================================================================
# EKS CLUSTER OUTPUTS
# =============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}


output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for the EKS cluster"
  value       = module.eks.oidc_provider_arn
}

output "cluster_iam_role_name" {
  description = "IAM role name for the EKS cluster"
  value       = module.eks.cluster_iam_role_name
}

# =============================================================================
# EKS SECURITY OUTPUTS
# =============================================================================

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

output "cluster_service_cidr" {
  description = "The CIDR block for the cluster service"
  value       = module.eks.cluster_service_cidr
}

# =============================================================================
# DATABASE OUTPUTS
# =============================================================================

output "database_endpoint" {
  description = "Database endpoint"
  value       = module.database.db_instance_endpoint
}

output "database_port" {
  description = "Database port"
  value       = module.database.db_instance_port
}

output "database_name" {
  description = "Database name"
  value       = module.database.db_instance_name
}

output "database_username" {
  description = "Database username"
  value       = module.database.db_instance_username
  sensitive   = true
}

output "database_identifier" {
  description = "Database identifier"
  value       = module.database.db_instance_id
}

output "database_security_group_id" {
  description = "The security group ID of the database"
  value       = module.database.db_security_group_id
}

# =============================================================================
# S3 STORAGE OUTPUTS
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.storage.bucket_name
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = module.storage.bucket_arn
}

output "s3_bucket_domain_name" {
  description = "The domain name of the S3 bucket"
  value       = module.storage.bucket_domain_name
}

output "materialize_s3_role_arn" {
  description = "The ARN of the IAM role for Materialize"
  value       = module.storage.materialize_s3_role_arn
}

# =============================================================================
# MATERIALIZE BACKEND URLS
# =============================================================================

output "metadata_backend_url" {
  description = "PostgreSQL connection URL in the format required by Materialize"
  value       = local.metadata_backend_url
  sensitive   = true
}

output "persist_backend_url" {
  description = "S3 connection URL in the format required by Materialize using IRSA"
  value       = local.persist_backend_url
}

# =============================================================================
# MATERIALIZE OPERATOR OUTPUTS
# =============================================================================

output "operator_namespace" {
  description = "Materialize operator namespace"
  value       = var.operator_namespace
}

output "operator_release_name" {
  description = "Helm release name of the operator"
  value       = module.operator.operator_release_name
}

output "operator_release_status" {
  description = "Status of the helm release"
  value       = module.operator.operator_release_status
}

# =============================================================================
# MATERIALIZE INSTANCE OUTPUTS
# =============================================================================

output "instance_resource_id" {
  description = "Materialize instance resource ID"
  value       = module.materialize_instance.instance_resource_id
}

# =============================================================================
# NETWORK LOAD BALANCER OUTPUTS
# =============================================================================

output "nlb_details" {
  description = "Details of the Materialize instance NLBs."
  value = {
    arn      = try(module.materialize_nlb.nlb_arn, null)
    dns_name = try(module.materialize_nlb.nlb_dns_name, null)
    security_group_id = try(module.materialize_nlb.nlb_security_group_id, null)
  }
}

# =============================================================================
# CERTIFICATE OUTPUTS
# =============================================================================

output "cluster_issuer_name" {
  description = "Name of the cluster issuer"
  value       = module.self_signed_cluster_issuer.issuer_name
}
