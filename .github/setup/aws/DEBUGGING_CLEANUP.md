# AWS CI Setup - Debugging and Cleanup Guide

Manual cleanup guide when CI fails to destroy AWS resources.

> Replace `YOUR_ACCOUNT_ID` with your actual AWS account ID throughout this document.

## Prerequisites

- AWS CLI, Terraform, kubectl, helm installed
- S3 access to retrieve state files

## Steps

### 1. Download State Files from S3

The CI automatically uploads both state and variable files to S3 during the apply phase:

```bash
# Download terraform state file
aws s3 cp s3://your-terraform-state-bucket/test-runs/aws/RUN_ID/STAGE_NAME/terraform.tfstate ./terraform.tfstate

# Download terraform variables file  
aws s3 cp s3://your-terraform-state-bucket/test-runs/aws/RUN_ID/STAGE_NAME/terraform.tfvars.json ./terraform.tfvars.json
```

Replace:
- `your-terraform-state-bucket` with actual S3 bucket
- `RUN_ID` with your test run ID 
- `STAGE_NAME` with stage name (`networking` or `materialize-disk-enabled`/`materialize-disk-disabled`)

### 2. Copy to Fixture Directory

```bash
# For materialize fixtures
cp terraform.tfstate terraform.tfvars test/aws/fixtures/materialize/

# For networking fixtures  
cp terraform.tfstate terraform.tfvars test/aws/fixtures/networking/
```

### 3. Create Cleanup User

```bash
# Create user and get ARN
aws iam create-user --user-name terraform-cleanup-user
aws iam get-user --user-name terraform-cleanup-user --query 'User.Arn' --output text

# Create access keys
aws iam create-access-key --user-name terraform-cleanup-user
```

### 4. Configure Role Trust Policy

Add user ARN to `.github/setup/aws/terraform.tfvars`:

```hcl
user_role_arn = "arn:aws:iam::YOUR_ACCOUNT_ID:user/terraform-cleanup-user"
```

Apply the change:
```bash
cd .github/setup/aws && terraform apply
```

### 5. Configure AWS Profile

```bash
aws configure --profile terraform-cleanup
# Enter access key and secret from step 3
```

### 6. Update Provider Configuration

Ensure your fixture's `main.tf` has role assumption configured:

```hcl
provider "aws" {
  region  = var.region
  profile = var.profile
  assume_role {
    role_arn     = "arn:aws:iam::YOUR_ACCOUNT_ID:role/mz-self-managed-github-actions-role"
    session_name = "terraform-cleanup"
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "--profile", var.profile,
      "eks", "get-token",
      "--role-arn", "arn:aws:iam::YOUR_ACCOUNT_ID:role/mz-self-managed-github-actions-role",
      "--cluster-name", module.eks.cluster_name
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "--profile", var.profile,
        "eks", "get-token", 
        "--role-arn", "arn:aws:iam::YOUR_ACCOUNT_ID:role/mz-self-managed-github-actions-role",
        "--cluster-name", module.eks.cluster_name
      ]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "--profile", var.profile,
      "eks", "get-token",
      "--role-arn", "arn:aws:iam::YOUR_ACCOUNT_ID:role/mz-self-managed-github-actions-role", 
      "--cluster-name", module.eks.cluster_name
    ]
  }
  load_config_file = false
}
```

### 7. Backend Configuration (Optional)

To use local state instead of S3 backend, comment out the backend block in fixtures versions.tf:
```hcl
# terraform {
#   backend "s3" { ... }
# }
```

### 8. Cleanup Resources

```bash
cd test/aws/fixtures/materialize/  # or networking/
export AWS_PROFILE=terraform-cleanup

terraform init
terraform destroy -auto-approve
```

## Debugging Commands

```bash
# Test credentials and role assumption
aws sts get-caller-identity --profile terraform-cleanup
aws sts assume-role --role-arn "arn:aws:iam::YOUR_ACCOUNT_ID:role/mz-self-managed-github-actions-role" --role-session-name "debug" --profile terraform-cleanup

# Enable debug logging
export TF_LOG=DEBUG
```
