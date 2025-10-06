# Networking outputs
output "networking" {
  description = "Networking details"
  value = {
    vpc_id             = module.networking.vpc_id
    private_subnet_ids = module.networking.private_subnet_ids
    public_subnet_ids  = module.networking.public_subnet_ids
  }
}

# Cluster outputs
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "generic_node_group_id" {
  description = "ID of the generic node group"
  value       = module.generic_node_group.node_group_id
}

output "generic_node_group_arn" {
  description = "ARN of the generic node group"
  value       = module.generic_node_group.node_group_arn
}

output "materialize_node_group_id" {
  description = "ID of the Materialize node group"
  value       = module.materialize_node_group.node_group_id
}

output "materialize_node_group_arn" {
  description = "ARN of the Materialize node group"
  value       = module.materialize_node_group.node_group_arn
}

# Database outputs
output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = module.database.db_instance_endpoint
}

output "database_name" {
  description = "RDS instance name"
  value       = module.database.db_instance_name
}

output "database_username" {
  description = "RDS instance username"
  value       = module.database.db_instance_username
  sensitive   = true
}

# Storage outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.storage.bucket_name
}

output "materialize_s3_role_arn" {
  description = "The ARN of the IAM role for Materialize"
  value       = module.storage.materialize_s3_role_arn
}

# Materialize component outputs
output "operator" {
  description = "Materialize operator details"
  value = {
    namespace      = module.operator.operator_namespace
    release_name   = module.operator.operator_release_name
    release_status = module.operator.operator_release_status
  }
}

output "materialize_instance_name" {
  description = "Materialize instance name"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_name : null
}

output "materialize_instance_namespace" {
  description = "Materialize instance namespace"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_namespace : null
}

output "materialize_instance_resource_id" {
  description = "Materialize instance resource ID"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_resource_id : null
}

output "materialize_instance_metadata_backend_url" {
  description = "Materialize instance metadata backend URL"
  value       = var.install_materialize_instance ? module.materialize_instance[0].metadata_backend_url : null
  sensitive   = true
}

output "materialize_instance_persist_backend_url" {
  description = "Materialize instance persist backend URL"
  value       = var.install_materialize_instance ? module.materialize_instance[0].persist_backend_url : null
  sensitive   = true
}

# Load balancer outputs
output "nlb_details" {
  description = "Details of the Materialize instance NLBs."
  value = {
    arn      = try(module.materialize_nlb[0].nlb_arn, null)
    dns_name = try(module.materialize_nlb[0].nlb_dns_name, null)
  }
}
