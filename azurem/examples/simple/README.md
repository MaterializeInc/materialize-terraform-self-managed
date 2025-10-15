# Example: Simple Materialize Deployment on Azure

This example demonstrates how to deploy a complete Materialize environment on Azure using the modular Terraform setup from this repository.

It provisions the full infrastructure stack, including:
- Virtual Network with AKS and PostgreSQL subnets
- AKS cluster with system and workload node pools
- Azure Database for PostgreSQL Flexible Server
- Azure Storage Account with blob container
- OpenEBS for disk support
- Cert-manager for TLS certificates
- Materialize operator

---

## Getting Started

### Step 1: Set Required Variables

Before running Terraform, create a `terraform.tfvars` file or pass the following variables:

```hcl
subscription_id = "12345678-1234-1234-1234-123456789012"
name_prefix = "simple-demo"
location = "westus2"
```

---

### Step 2: Deploy the Infrastructure

Run the usual Terraform workflow:

```bash
terraform init
terraform apply
```

## Notes

* You can customize each module independently.
* To reduce cost in your demo environment, you can tweak VM sizes and database tiers in `main.tf`.
* Don't forget to destroy resources when finished:

```bash
terraform destroy
```
