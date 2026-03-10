output "role_arn" {
  description = "The ARN of the IAM role for cert-manager (IRSA annotation value)."
  value       = aws_iam_role.cert_manager.arn
}
