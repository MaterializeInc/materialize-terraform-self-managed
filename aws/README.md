# Materialize on AWS Terraform Modules

This repository provides a set of reusable, **self-contained Terraform modules** to deploy Materialize on the AWS cloud platform. You can use these modules individually or combine them to create your own custom infrastructure stack.

> **Note**
> These modules are intended for demonstration and prototyping purposes. If you're planning to use them in production, fork the repo and pin to a specific commit or tag to avoid breaking changes in future versions.

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
