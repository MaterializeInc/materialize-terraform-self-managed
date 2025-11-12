# Example: Simple Materialize Deployment on AWS

This example demonstrates how to deploy a complete Materialize environment on AWS using the modular Terraform setup from this repository.

---

## What Gets Created

This example provisions the following infrastructure:

### Networking
- **VPC**: 10.0.0.0/16 with DNS hostnames and support enabled
- **Subnets**: 3 private subnets (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24) and 3 public subnets (10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24) across availability zones us-east-1a, us-east-1b, us-east-1c
- **NAT Gateway**: Single NAT Gateway for all private subnets
- **Internet Gateway**: For public subnet connectivity

### Compute
- **EKS Cluster**: Version 1.32 with CloudWatch logging (API, audit)
- **Base Node Group**: 2 nodes (t4g.medium) for Karpenter and CoreDNS
- **Karpenter**: Auto-scaling controller with two node classes:
  - Generic nodepool: t4g.xlarge instances for general workloads
  - Materialize nodepool: r7gd.2xlarge instances with swap enabled and dedicated taints to run materialize instance workloads.

### Database
- **RDS PostgreSQL**: Version 15, db.t3.large instance
- **Storage**: 50GB allocated, autoscaling up to 100GB
- **Deployment**: Single-AZ (non-production configuration)
- **Backups**: 7-day retention
- **Security**: Dedicated security group with access from EKS cluster and nodes

### Storage
- **S3 Bucket**: Dedicated bucket for Materialize persistence
- **Encryption**: Disabled (for testing; enable in production)
- **Versioning**: Disabled (for testing; enable in production)
- **IAM Role**: IRSA role for Kubernetes service account access

### Kubernetes Add-ons
- **AWS Load Balancer Controller**: For managing Network Load Balancers
- **cert-manager**: Certificate management controller for Kubernetes that automates TLS certificate provisioning and renewal
- **Self-signed ClusterIssuer**: Provides self-signed TLS certificates for Materialize instance internal communication (balancerd, console). Used by the Materialize instance for secure inter-component communication.

### Materialize
- **Operator**: Materialize Kubernetes operator
- **Instance**: Single Materialize instance in `materialize-environment` namespace
- **Network Load Balancer**: Dedicated internal NLB for Materialize access (ports 6875, 6876, 8080)

---

## Getting Started

### Step 1: Set Required Variables

Before running Terraform, create a `terraform.tfvars` file with the following variables:

```hcl
name_prefix = "simple-demo"
aws_region  = "us-east-1"
aws_profile = "your-aws-profile"
license_key = "your-materialize-license-key"  # Get from https://materialize.com/self-managed/
tags = {
  environment = "demo"
}
```

**Required Variables:**
- `name_prefix`: Prefix for all resource names
- `aws_region`: AWS region for deployment
- `aws_profile`: AWS CLI profile to use
- `tags`: Map of tags to apply to resources
- `license_key`: Materialize license key

---

### Step 2: Deploy Materialize

Run the usual Terraform workflow:

```bash
terraform init
terraform apply
```

---

## Notes

* You can customize each module independently.
* To reduce cost in your demo environment, you can tweak subnet CIDRs and instance types in `main.tf`.
* Don't forget to destroy resources when finished:

```bash
terraform destroy
```
