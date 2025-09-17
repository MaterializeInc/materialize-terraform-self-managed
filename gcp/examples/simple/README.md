# Example: Simple Materialize Deployment on GCP

This example demonstrates how to deploy a complete Materialize environment on Google Cloud Platform using the modular Terraform setup from this repository.

It provisions the full infrastructure stack, including:
- VPC network with subnets for GKE and Cloud SQL
- GKE cluster with node pools
- Cloud SQL PostgreSQL database for metadata
- Google Cloud Storage bucket for persistent storage
- Workload Identity for secure service access
- Materialize operator

> **Important:**
> Due to a limitation with the `kubernetes_manifest` resource in Terraform, the Materialize instance **cannot be installed on the first run**. The Kubernetes cluster must be fully provisioned before applying the instance configuration.

---

### 2. Required APIs
Your GCP project needs several APIs enabled. Here's what each API does in simple terms:

```bash
# Enable these APIs in your project
gcloud services enable container.googleapis.com               # For creating Kubernetes clusters
gcloud services enable sqladmin.googleapis.com                # For creating databases
gcloud services enable cloudresourcemanager.googleapis.com    # For managing GCP resources
gcloud services enable servicenetworking.googleapis.com       # For private network connections
gcloud services enable iamcredentials.googleapis.com          # For security and authentication
```

## Getting Started

### Step 1: Set Required Variables

Before running Terraform, create a `terraform.tfvars` file or pass the following variables:

```hcl
project_id = "my-gcp-project"
name_prefix = "simple-demo"
install_materialize_instance = false
region = "us-central1"
```

---

### Step 2: Deploy the Infrastructure

Run the usual Terraform workflow:

```bash
terraform init
terraform apply
```

This will provision all infrastructure components except the Materialize instance.

---

### Step 3: Deploy the Materialize Instance

Once the initial deployment completes successfully:

1. Update your variable:

   ```hcl
   install_materialize_instance = true
   ```

2. Run `terraform apply` again to deploy the instance.

---

## Notes

* You can customize each module independently.
* To reduce cost in your demo environment, you can tweak machine types and database tiers in `main.tf`.
* Don't forget to destroy resources when finished:

```bash
terraform destroy
```
