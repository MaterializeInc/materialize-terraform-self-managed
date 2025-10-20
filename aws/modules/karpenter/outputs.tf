output "node_instance_profile" {
  description = "Name of the instance profile to assign to nodes."
  value       = aws_iam_instance_profile.node.name
}
