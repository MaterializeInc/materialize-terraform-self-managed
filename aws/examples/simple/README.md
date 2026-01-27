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
- **Network Load Balancer**: Internet-facing NLB for Materialize access (ports 6875, 6876, 8080)

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

**Optional Variables:**
- `k8s_apiserver_authorized_networks`: List of CIDR blocks allowed to access the EKS cluster endpoint (defaults to `["0.0.0.0/0"]`)
- `ingress_cidr_blocks`: List of CIDR blocks allowed to reach the Load Balancer (defaults to `["0.0.0.0/0"]`)
- `internal_load_balancer`: Whether to use an internal load balancer (defaults to `true`)

### Configuring Cluster Endpoint Public Access CIDRs

To restrict EKS API server access to specific IP ranges:

1. Get your public IP and convert to CIDR:
```bash
MY_IP=$(curl -s https://ipinfo.io/ip)
MY_IP_CIDR="${MY_IP}/32"  # Single IP, or use: whois $MY_IP | grep route
echo $MY_IP_CIDR
```

2. Add to `terraform.tfvars`:
```hcl
k8s_apiserver_authorized_networks = ["X.X.X.X/32"]  # Replace with your IP from step 1
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

---

### Step 3: Accessing Materialize

#### Security Model
This deployment implements a secure access model:
- **Public Access**: Only allowed via the Network Load Balancer (NLB).
- **Direct Node Access**: **BLOCKED**. The EKS nodes have a security group that only accepts traffic from within the VPC.

#### Access Methods

**If using a public (internet-facing) NLB:**

Both SQL and Console are available via the public NLB:

- **SQL Access**: Connect using any PostgreSQL-compatible client pointing to the NLB's DNS name on port **6875**
- **Console Access**: Access the Materialize Console via the NLB's DNS name on port **8080**

To get the NLB DNS name:
```bash
terraform output -json | jq -r .nlb_dns_name.value
```

**If using a private (internal) NLB:**

Use Kubernetes port-forwarding for both SQL and Console. `kubectl port-forward` creates a TCP tunnel that preserves the underlying protocol (pgwire for SQL, HTTP for Console):

- **SQL Access**:
```bash
# Forward local port 6875 to the Materialize balancerd service
kubectl port-forward svc/mz<resource-id>-balancerd 6875:6875 -n materialize-environment
```
Then connect your PostgreSQL client to `localhost:6875`. The pgwire protocol is preserved through the TCP tunnel.

- **Console Access**:
```bash
# Forward local port 8080 to the Materialize console service
kubectl port-forward svc/mz<resource-id>-console 8080:8080 -n materialize-environment
```
Then open your browser to `http://localhost:8080`. HTTP traffic is preserved through the TCP tunnel.

**Note on NLB Layer 4 operation:**
The NLB operates at Layer 4 (TCP), forwarding connections without interpreting application-layer protocols. This works correctly for both pgwire (port 6875) and HTTP console access (port 8080), as both protocols run over TCP. The NLB forwards the TCP packets to the backend services, which handle the respective protocols.

---

### Step 4: Accessing Grafana

Grafana is deployed in the `monitoring` namespace with pre-configured Materialize dashboards.

#### Port Forwarding

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

Then open [http://localhost:3000](http://localhost:3000) in your browser.

#### Login Credentials

- **Username:** `admin`
- **Password:** Retrieve from Terraform output:

```bash
terraform output -raw grafana_admin_password
```

#### Pre-configured Dashboards

The deployment includes Materialize dashboards under the "Materialize" folder:
- **Environment Overview** - Overall Materialize environment health
- **Freshness Overview** - Data freshness monitoring

---

## Prometheus Resource Sizing Recommendations

The default Prometheus resource limits (500m CPU / 512Mi memory request, 1 CPU / 1Gi memory limit) are suitable for small deployments monitoring a single Materialize environment with default scrape intervals.

For production deployments, consider increasing resources based on:
- **Number of scrape targets**: More targets = more memory for time series
- **Scrape interval**: Lower intervals increase CPU and memory usage
- **Retention period**: Longer retention requires more storage and memory
- **Query complexity**: Heavy dashboard usage increases CPU needs

Example configuration for medium workload in `main.tf`:

```hcl
module "prometheus" {
  source = "../../../kubernetes/modules/prometheus"
  # ...
  server_resources = {
    requests = {
      cpu    = "1000m"
      memory = "2Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "4Gi"
    }
  }
  storage_size = "100Gi"
}
```

---

## Cluster Sizes and Instance Types

The Karpenter Materialize nodepool is configured to use `r7gd.2xlarge` instances by default. This instance type has:
- **8 vCPUs**
- **64 GiB RAM**
- **NVMe SSD** (for swap)

### Supported Cluster Sizes

With the default `r7gd.2xlarge` instance type, you can create Materialize clusters up to approximately **300cc**. Larger cluster sizes (e.g., `600cc`) require more resources than a single `r7gd.2xlarge` can provide. Checkout [materialize self-managed documentation](https://materialize.com/docs/self-managed-deployments/appendix/appendix-cluster-sizes/#default-cluster-sizes) for more information about supported cluster sizes.
### Configuring Larger Instance Types

To support larger cluster sizes, modify the `instance_types_materialize` variable in `main.tf`:

```hcl
# Default (supports up to ~300cc)
instance_types_materialize = ["r7gd.2xlarge"]

# For larger clusters (supports up to ~600cc)
instance_types_materialize = ["r7gd.4xlarge"]

# For very large clusters (supports up to ~1200cc)
instance_types_materialize = ["r7gd.8xlarge"]
```

**Instance Type Reference:**

| Instance Type | vCPUs | Memory | Max Cluster Size               |
|---------------|-------|--------|--------------------------------|
| r7gd.2xlarge  | 8     | 64 GiB | ~300cc                         |
| r7gd.4xlarge  | 16    | 128 GiB| ~600cc                         |
| r7gd.8xlarge  | 32    | 256 GiB| ~1200cc                        |
| r7gd.16xlarge | 64    | 512 GiB| ~3200cc                        |

**Important Notes:**
- All `r7gd` instances include local NVMe SSD storage required for swap
- Larger instances have higher costs but support larger Materialize clusters
- Instance availability varies by region/zone; verify availability in your target region
- The kube-reserved memory calculations are based on the largest configured instance type. Specifying multiple instance types with different CPU or RAM capacities may result in some instance types having inefficient kube-reserved values.

---

## Notes

* You can customize each module independently.
* To reduce cost in your demo environment, you can tweak subnet CIDRs and instance types in `main.tf`.
* Don't forget to destroy resources when finished:

```bash
terraform destroy
```
