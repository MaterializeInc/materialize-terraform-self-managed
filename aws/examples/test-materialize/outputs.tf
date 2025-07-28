
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.storage.bucket_name
}

output "metadata_backend_url" {
  description = "PostgreSQL connection URL in the format required by Materialize"
  value       = local.metadata_backend_url
  sensitive   = true
}

output "persist_backend_url" {
  description = "S3 connection URL in the format required by Materialize using IRSA"
  value       = local.persist_backend_url
}

output "materialize_s3_role_arn" {
  description = "The ARN of the IAM role for Materialize"
  value       = module.operator.materialize_s3_role_arn
}

output "nlb_details" {
  description = "Details of the Materialize instance NLBs."
  value = {
    arn      = try(module.materialize_nlb[0].nlb_arn, null)
    dns_name = try(module.materialize_nlb[0].nlb_dns_name, null)
  }
}

output "instance_resource_id" {
  description = "Materialize instance resource ID"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_resource_id : null
}

# Certificate outputs
output "cluster_issuer_name" {
  description = "Name of the cluster issuer"
  value       = module.certificates.cluster_issuer_name
}

# OpenEBS outputs
output "openebs_installed" {
  description = "Whether OpenEBS was installed"
  value       = module.openebs.openebs_installed
}

output "openebs_namespace" {
  description = "The namespace where OpenEBS is installed"
  value       = module.openebs.openebs_namespace
}

# Operator outputs
output "operator_namespace" {
  description = "Materialize operator namespace"
  value       = var.operator_namespace
}

# Instance outputs
output "instance_installed" {
  description = "Whether Materialize instance was installed"
  value       = var.install_materialize_instance
}
