output "iam_role_arn" {
  description = "ARN of the IAM role for the EBS CSI driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "storage_class_name" {
  description = "Name of the default storage class created"
  value       = kubernetes_storage_class.gp3.metadata[0].name
}
