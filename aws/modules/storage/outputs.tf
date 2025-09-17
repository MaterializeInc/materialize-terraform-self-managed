output "bucket_id" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.materialize_storage.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.materialize_storage.arn
}

output "bucket_domain_name" {
  description = "The domain name of the S3 bucket"
  value       = aws_s3_bucket.materialize_storage.bucket_domain_name
}

output "bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.materialize_storage.bucket
}

output "materialize_s3_role_arn" {
  description = "ARN of the IAM role for Materialize S3 access"
  value       = aws_iam_role.materialize_s3.arn
}
