# Materialize on AWS Terraform Modules

This repository provides a set of reusable, **self-contained Terraform modules** to deploy Materialize on the AWS cloud platform. You can use these modules individually or combine them to create your own custom infrastructure stack.

-> **Note**
-> We recommend pinning your module sources to specific tags to avoid unexpected breaking changes in future versions.
-> We recommend updating your module source tags when updating Materialize versions, taking care to follow any instructions in the release notes.

---

## Prerequisites

Before using these modules, ensure you have the following tools installed:

- [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.0)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (required for cleaning up Karpenter NodeClaims)

---

## Modular Architecture

Each module is designed to be used independently. You can compose them in any way that fits your use case.

See [`examples/simple/`](./examples/simple/) for a working example that ties the modules together into a complete environment.

---

## Available Modules

AWS Specific Modules:

| Module                                                | Description                                                 |
|-------------------------------------------------------|-------------------------------------------------------------|
| [`modules/networking`](./modules/networking)          | VPC, subnets, NAT gateways, and networking resources        |
| [`modules/eks`](./modules/eks)                        | EKS cluster with OIDC provider and security groups          |
| [`modules/eks-node-group`](./modules/eks-node-group)  | EKS managed node groups for base workloads                  |
| [`modules/karpenter`](./modules/karpenter)            | Karpenter for advanced node autoscaling                     |
| [`modules/karpenter-ec2nodeclass`](./modules/karpenter-ec2nodeclass) | EC2NodeClass for Karpenter provisioning     |
| [`modules/karpenter-nodepool`](./modules/karpenter-nodepool) | NodePool for Karpenter workload scheduling  |
| [`modules/database`](./modules/database)              | RDS PostgreSQL database for Materialize metadata           |
| [`modules/storage`](./modules/storage)                | S3 bucket with IRSA for Materialize persistence            |
| [`modules/aws-lbc`](./modules/aws-lbc)                | AWS Load Balancer Controller for NLB management            |
| [`modules/nlb`](./modules/nlb)                        | Network Load Balancer for Materialize instance access      |
| [`modules/operator`](./modules/operator)              | Materialize Kubernetes operator installation               |
| [`modules/monitoring`](./modules/monitoring)           | Observability stack (Loki, Thanos, Grafana, Alloy) with S3 buckets and IRSA roles |

**Cloud-Agnostic Kubernetes Modules:**

For Kubernetes-specific modules (cert-manager, Materialize instance, etc.) that work across all cloud providers, see the [kubernetes/](../kubernetes/) directory.

See the [Kubernetes Modules README](../kubernetes/README.md) for details on:
- cert-manager installation
- Self-signed certificate issuer
- Materialize instance deployment

---

Depending on your needs, you can use the modules individually or combine them to create a setup that fits your needs.

---

## Getting Started

### Example Deployment

To deploy a simple end-to-end environment, see the [`examples/simple`](./examples/simple) folder.

```hcl
module "networking" {
  source = "../../modules/networking"
  name_prefix = "mz"
  # ... networking vars
}

module "eks" {
  source = "../../modules/eks"
  name_prefix = "mz"
  vpc_id = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  # ... eks vars
}

# See full working setup in the examples/simple/main.tf file
```

---

## Multi-AZ Configuration

These modules are designed for multi-AZ deployments to provide high availability. This section explains how availability zone configuration flows through the infrastructure.

### How It Works

The `availability_zones` parameter in the networking module determines the AZ topology for your entire deployment:

```hcl
module "networking" {
  source = "../../modules/networking"

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]  # 3 AZs
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  # ...
}
```

Each availability zone gets:
- One **private subnet** for EKS nodes, Materialize workloads, and RDS
- One **public subnet** for NAT gateways and public-facing load balancers

The networking module outputs `private_subnet_ids` and `public_subnet_ids`, which downstream modules use to distribute resources across all configured AZs.

### Component Distribution

| Component | Multi-AZ Behavior |
|-----------|-------------------|
| **EKS Node Groups** | Nodes distributed across all private subnets/AZs via `subnet_ids` |
| **Karpenter EC2NodeClass** | Can provision nodes in any AZ via `subnet_ids`; selects optimal zone per pod |
| **EBS Volumes** | Created in same AZ as the consuming pod (`WaitForFirstConsumer` binding) |
| **Network Load Balancer** | Deployed in all configured subnets; cross-zone LB enabled by default |
| **RDS Database** | Supports multi-AZ with synchronous standby (`multi_az = true`) |
| **S3 Bucket** | Regionally replicated by AWS (inherently multi-AZ) |

### NAT Gateway Options

The networking module's `single_nat_gateway` variable controls NAT gateway topology:

| Setting | Behavior | Cost | Availability |
|---------|----------|------|--------------|
| `true` (default) | One NAT gateway shared by all AZs | Lower | Single point of failure; cross-AZ traffic |
| `false` | One NAT gateway per AZ | Higher | No cross-AZ dependency; traffic stays in-zone |

For production workloads, consider `single_nat_gateway = false` to eliminate NAT gateway as a single point of failure.

### EBS Storage and Zone Affinity

The EBS CSI driver creates a `gp3` StorageClass with `WaitForFirstConsumer` volume binding mode. This ensures:

1. PVCs remain unbound until a pod references them
2. The scheduler picks a node (and thus an AZ) for the pod
3. The EBS volume is provisioned in the same AZ as the selected node

This prevents cross-AZ volume attachment failures, which would occur if a volume were created in a different AZ than its pod.

### RDS Multi-AZ

The database module defaults to `multi_az = false` for cost savings. For production:

```hcl
module "database" {
  source   = "../../modules/database"
  multi_az = true  # Enable for production
  # ...
}
```

With `multi_az = true`:
- RDS maintains a synchronous standby in a different AZ
- Automatic failover occurs during AZ outages or maintenance
- The `database_subnet_ids` (spanning all AZs) allows RDS to place instances optimally

### Cross-AZ Data Transfer Costs

Multi-AZ deployments incur inter-AZ data transfer charges. Key cost considerations:

| Traffic Type | Cost Implication | Mitigation |
|--------------|------------------|------------|
| **NAT Gateway cross-AZ** | Charged when `single_nat_gateway = true` | Use `single_nat_gateway = false` |
| **NLB cross-zone** | Charged when `enable_cross_zone_load_balancing = true` | Disable if targets are balanced per-AZ |
| **Pod-to-pod cross-AZ** | Charged for inter-AZ pod communication | Use topology spread constraints |
| **EBS cross-AZ** | N/A - prevented by `WaitForFirstConsumer` | Already mitigated |

AWS charges approximately $0.01/GB for inter-AZ traffic within the same region. For cost-sensitive workloads, consider:
- Setting `single_nat_gateway = false` to keep egress traffic in-zone
- Using pod topology spread constraints to co-locate communicating services
- Monitoring cross-AZ traffic with VPC Flow Logs

---

### Providers

Ensure you configure the AWS, Kubernetes, and Helm providers. Here's a minimal setup:

```hcl
provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}
```
