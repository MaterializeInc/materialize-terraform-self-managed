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
gcloud services enable compute.googleapis.com                 # For creating GKE nodes and other compute resources
gcloud services enable sqladmin.googleapis.com                # For creating databases
gcloud services enable cloudresourcemanager.googleapis.com    # For managing GCP resources
gcloud services enable servicenetworking.googleapis.com       # For private network connections
gcloud services enable iamcredentials.googleapis.com          # For security and authentication
gcloud services enable iam.googleapis.com                     # For managing IAM service accounts and policies
gcloud services enable storage.googleapis.com                 # For Cloud Storage buckets
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

**Optional Variables:**
- `k8s_apiserver_authorized_networks`: List of authorized CIDR blocks for GKE API server access (defaults to `[{ cidr_block = "0.0.0.0/0", display_name = "Default Placeholder for authorized networks" }]`)
- `ingress_cidr_blocks`: List of CIDR blocks allowed to reach the Load Balancer (defaults to `["0.0.0.0/0"]`)
- `internal_load_balancer`: Whether to use an internal load balancer (defaults to `true`)

### Configuring GKE API server access to specific IP ranges

To restrict GKE API server access to specific IP ranges:

1. Get your public IP and convert to CIDR:
```bash
MY_IP=$(curl -s https://ipinfo.io/ip)
MY_IP_CIDR="${MY_IP}/32"  # Single IP, or use: whois $MY_IP | grep route
echo $MY_IP_CIDR
```

2. Add to `terraform.tfvars`:
```hcl
k8s_apiserver_authorized_networks = [
  {
    cidr_block   = "X.X.X.X/32"  # Replace with your IP from step 1
    display_name = "My office network"
  },
  {
    cidr_block   = "203.0.113.0/24"
    display_name = "VPN endpoint"
  }
]
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
- **Public Access**: Only allowed via the GCP Load Balancer.
- **Direct Node Access**: **BLOCKED**. The GKE nodes are in private subnets and only accept traffic from within the VPC.

#### Access Methods

**If using a public (external) Load Balancer:**

Both SQL and Console are available via the public Load Balancer:

- **SQL Access**: Connect using any PostgreSQL-compatible client pointing to the Load Balancer's IP on port **6875**
- **Console Access**: Access the Materialize Console via the Load Balancer's IP on port **8080**

To get the Load Balancer IP:
```bash
kubectl get svc -n materialize-environment -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}'
```

Connect using psql with the superuser credentials:
```bash
# Get credentials (use jq -r to decode JSON-escaped characters)
terraform output -json mz_instance_superuser_credentials | jq -r '"Username: \(.username)\nPassword: \(.password)"'

psql -h <LoadBalancerIP> -p 6875 -U <username>
```

**If using a private (internal) Load Balancer:**

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

**Note on Load Balancer Layer 4 operation:**
The Load Balancer operates at Layer 4 (TCP), forwarding connections without interpreting application-layer protocols. This works correctly for both pgwire (port 6875) and HTTP console access (port 8080), as both protocols run over TCP.

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

The deployment includes Materialize dashboards under the "kubernetes/grafana" folder:
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

## Notes

* You can customize each module independently.
* To reduce cost in your demo environment, you can tweak machine types and database tiers in `main.tf`.
* Don't forget to destroy resources when finished:

```bash
terraform destroy
```
