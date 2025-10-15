# Example: Simple Materialize Deployment on AWS

This example demonstrates how to deploy a complete Materialize environment on AWS using the modular Terraform setup from this repository.

It provisions the full infrastructure stack, including:
- VPC and networking
- EKS cluster and node group
- RDS PostgreSQL for metadata
- S3 for persistent storage
- Load Balancer Controller and cert-manager
- Materialize operator

---

## Getting Started

### Step 1: Set Required Variables

Before running Terraform, create a `terraform.tfvars` file or pass the following variables:

```hcl
name_prefix = "simple-demo"
aws_region = "us-east-1"
aws_profile = "test-profile"
````

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
