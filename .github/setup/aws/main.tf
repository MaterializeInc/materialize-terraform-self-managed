# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "mz-self-managed-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:MaterializeInc/materialize-terraform-self-managed:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "materialize-terraform-self-managed-github-actions-role"
  }
}

# Admin policy for GitHub Actions (simplified for testing)
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
