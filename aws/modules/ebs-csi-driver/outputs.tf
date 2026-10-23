output "iam_role_arn" {
  description = "ARN of the IAM role for the EBS CSI driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "storage_class_name" {
  description = "Name of the default storage class created"
  value       = kubernetes_storage_class.gp3.metadata[0].name

  # Orders the destroy of anything that uses this storage class ahead of the
  # volume drain, so the drain waits on volumes that are actually being let go.
  depends_on = [terraform_data.volume_drain]
}
