# Example: Simple Materialize Deployment on Azure

This example demonstrates how to deploy a complete Materialize environment on Azure using the modular Terraform setup from this repository.

---

## What Gets Created

This example provisions the following infrastructure:

### Resource Group
- **Resource Group**: New resource group to contain all resources

### Networking
- **Virtual Network**: 20.0.0.0/16 address space
- **AKS Subnet**: 20.0.0.0/20 with NAT Gateway association and service endpoints for Storage and SQL
- **PostgreSQL Subnet**: 20.0.16.0/24 delegated to PostgreSQL Flexible Server
- **NAT Gateway**: Standard SKU with static public IP for outbound connectivity
- **Private DNS Zone**: For PostgreSQL private endpoint resolution with VNet link

### Compute
- **AKS Cluster**: Version 1.32 with Cilium networking (network plugin: azure, data plane: cilium, policy: cilium)
- **Default Node Pool**: Standard_D4pds_v6 VMs, autoscaling 2-5 nodes, labeled for generic workloads
- **Materialize Node Pool**: Standard_E4pds_v6 VMs with 100GB disk, autoscaling 2-5 nodes, swap enabled, dedicated taints for Materialize workloads
- **Managed Identities**:
  - AKS cluster identity: Used by AKS control plane to provision Azure resources (creating load balancers when Materialize LoadBalancer services are created, managing network interfaces)
  - Workload identity: Used by Materialize pods for secure, passwordless authentication to Azure Storage (no storage account keys stored in cluster)

### Database
- **Azure PostgreSQL Flexible Server**: Version 15
- **SKU**: GP_Standard_D2s_v3 (2 vCores, 4GB memory)
- **Storage**: 32GB with 7-day backup retention
- **Network Access**: Public Network Access is disabled, Private access only (no public endpoint)
- **Database**: `materialize` database pre-created

### Storage
- **Storage Account**: Premium BlockBlobStorage with LRS replication for Materialize persistence
- **Container**: `materialize` blob container
- **Access Control**: Workload Identity federation for Kubernetes service account (passwordless authentication via OIDC)
- **Network Access**: Currently allows all traffic (production deployments should restrict to AKS subnet only traffic)

### Kubernetes Add-ons
- **cert-manager**: Certificate management controller for Kubernetes that automates TLS certificate provisioning and renewal
- **Self-signed ClusterIssuer**: Provides self-signed TLS certificates for Materialize instance internal communication (balancerd, console). Used by the Materialize instance for secure inter-component communication.

### Materialize
- **Operator**: Materialize Kubernetes operator
- **Instance**: Single Materialize instance in `materialize-environment` namespace
- **Load Balancers**: Internal Azure Load Balancers for Materialize access

---

## Getting Started

### Step 1: Set Required Variables

Before running Terraform, create a `terraform.tfvars` file with the following variables:

```hcl
subscription_id     = "12345678-1234-1234-1234-123456789012"
resource_group_name = "materialize-demo-rg"
name_prefix         = "simple-demo"
location            = "westus2"
license_key         = "your-materialize-license-key"  # Optional: Get from https://materialize.com/self-managed/
tags = {
  environment = "demo"
}
```

**Required Variables:**
- `subscription_id`: Azure subscription ID
- `resource_group_name`: Name for the resource group (will be created)
- `name_prefix`: Prefix for all resource names
- `location`: Azure region for deployment
- `tags`: Map of tags to apply to resources
- `license_key`: Materialize license key

**Optional Variables:**
- `api_server_authorized_ip_ranges`: List of authorized IP ranges for AKS API server access (defaults to `["0.0.0.0/0"]`)
- `ingress_cidr_blocks`: List of CIDR blocks allowed to reach the Load Balancer (defaults to `["0.0.0.0/0"]`)

### Configuring API Server Authorized IP Ranges

To restrict AKS API server access to your IP address:

1. Get your public IP and convert to CIDR:
```bash
MY_IP=$(curl -s https://ipinfo.io/ip)
MY_IP_CIDR="${MY_IP}/32"  # Single IP, or use: whois $MY_IP | grep route
echo $MY_IP_CIDR
```

2. Add to `terraform.tfvars`:
```hcl
api_server_authorized_ip_ranges = ["X.X.X.X/X"]  # Replace with your IP from step 1
```

**Note**: Public IP addresses may change since they are allocated by your ISP. These steps should be used in environments where the CIDR is static (e.g., corporate networks with fixed IP ranges, VPN endpoints, or static IP services). For dynamic IP environments, consider using broader CIDR ranges or alternative access methods.

### Configuring Load Balancer Ingress CIDR Blocks

To restrict Load Balancer access to specific IP ranges:

```hcl
ingress_cidr_blocks = ["203.0.113.0/24", "198.51.100.0/24"]
```

---

### Step 2: Deploy Materialize

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
