# Example: Simple Materialize Deployment on GCP

This example demonstrates how to deploy a complete Materialize environment on Google Cloud Platform using the modular Terraform setup from this repository.

---

## What Gets Created

This example provisions the following infrastructure:

### Networking
- **VPC Network**: Custom VPC with auto-create subnets disabled
- **Subnet**: 192.168.0.0/20 primary range with private Google access enabled
- **Secondary Ranges**: 
  - Pods: 192.168.64.0/18
  - Services: 192.168.128.0/20
- **Cloud Router**: For NAT and routing configuration
- **Cloud NAT**: For outbound internet access from private nodes
- **VPC Peering**: Service networking connection for Cloud SQL private access

### Compute
- **GKE Cluster**: Regional cluster with Workload Identity enabled
- **Generic Node Pool**: e2-standard-8 machines, autoscaling 2-5 nodes, 50GB disk, for general workloads
- **Materialize Node Pool**: n2-highmem-8 machines, autoscaling 2-5 nodes, 100GB disk, 1 local SSD, swap enabled, dedicated taints for Materialize workloads
- **Service Account**: GKE service account with workload identity binding

### Database
- **Cloud SQL PostgreSQL**: Private IP only (no public IP)
- **Tier**: db-custom-2-4096 (2 vCPUs, 4GB memory)
- **Database**: `materialize` database with UTF8 charset
- **User**: `materialize` user with auto-generated password
- **Network**: Connected via VPC peering for private access

### Storage
- **Cloud Storage Bucket**: Regional bucket for Materialize persistence
- **Access**: HMAC keys for S3-compatible access (Workload Identity service account with storage permissions is configured but not currently used by Materialize for GCS access, in future we will remove HMAC keys and support access to GCS either via Workload Identity Federation or via Kubernetes ServiceAccounts that impersonate IAM service accounts)
- **Versioning**: Disabled (for testing; enable in production)

### Kubernetes Add-ons
- **cert-manager**: Certificate management controller for Kubernetes that automates TLS certificate provisioning and renewal
- **Self-signed ClusterIssuer**: Provides self-signed TLS certificates for Materialize instance internal communication (balancerd, console). Used by the Materialize instance for secure inter-component communication.

### Materialize
- **Operator**: Materialize Kubernetes operator in `materialize` namespace
- **Instance**: Single Materialize instance in `materialize-environment` namespace
- **Load Balancers**: GCP Load Balancers for Materialize access

---

## Required APIs
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

Before running Terraform, create a `terraform.tfvars` file with the following variables:

```hcl
project_id  = "my-gcp-project"
name_prefix = "simple-demo"
region      = "us-central1"
license_key = "your-materialize-license-key"  # Optional: Get from https://materialize.com/self-managed/
labels = {
  environment = "demo"
  created_by  = "terraform"
}
```

**Required Variables:**
- `project_id`: GCP project ID
- `name_prefix`: Prefix for all resource names
- `region`: GCP region for deployment
- `labels`: Map of labels to apply to resources
- `license_key`: Materialize license key (required for production use)

---

### Step 2: Deploy Materialize

Run the usual Terraform workflow:

```bash
terraform init
terraform apply
```

## Notes

* You can customize each module independently.
* To reduce cost in your demo environment, you can tweak machine types and database tiers in `main.tf`.
* Don't forget to destroy resources when finished:

```bash
terraform destroy
```
