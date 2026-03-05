output "iam_role_arn" {
  description = "ARN of the IAM role used by the VPC CNI"
  value       = aws_iam_role.vpc_cni.arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by the VPC CNI"
  value       = aws_iam_role.vpc_cni.name
}

output "network_policy_enabled" {
  description = "Whether network policy support is enabled"
  value       = var.enable_network_policy
}

output "helm_release_name" {
  description = "Name of the Helm release"
  value       = helm_release.vpc_cni.name
}

output "helm_release_version" {
  description = "Version of the Helm chart installed"
  value       = helm_release.vpc_cni.version
}
