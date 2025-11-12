# Kubernetes Modules for Materialize

This directory contains cloud-agnostic Kubernetes modules for deploying and managing Materialize instances. These modules work across all supported cloud providers (AWS, Azure, GCP) and can be used with any Kubernetes cluster.

---

## Overview

The Kubernetes modules handle application-layer components that run on top of your Kubernetes infrastructure:
- Certificate management for TLS
- Materialize operator for managing Materialize instances
- Materialize instance deployment and configuration

These modules are designed to be cloud-agnostic and work with Kubernetes clusters provisioned by any cloud provider.

---

## Available Modules

| Module | Description |
|--------|-------------|
| [`cert-manager`](./modules/cert-manager) | Installs cert-manager for automated TLS certificate management |
| [`self-signed-cluster-issuer`](./modules/self-signed-cluster-issuer) | Creates a self-signed ClusterIssuer for internal TLS certificates |
| [`materialize-instance`](./modules/materialize-instance) | Deploys and configures a Materialize instance |

---

## Module Details

### cert-manager

Installs the cert-manager Helm chart for automated certificate lifecycle management in Kubernetes.

**Key Features:**
- Automated certificate provisioning and renewal
- Support for various certificate issuers (self-signed, Let's Encrypt, etc.)
- Configurable namespace and node scheduling

**Usage:** Required by Materialize instances for TLS certificate management.

**Documentation:** See [modules/cert-manager/README.md](./modules/cert-manager/README.md)

---

### self-signed-cluster-issuer

Creates a self-signed ClusterIssuer resource that cert-manager uses to issue self-signed TLS certificates.

**Key Features:**
- Self-signed certificate issuer for development and internal use
- Cluster-wide scope (ClusterIssuer)
- Used by Materialize for internal component communication (balancerd, console)

**Usage:** Optional convenience module. You can use your own certificate issuer instead (Let's Encrypt, organizational CA, etc.). Materialize instances just need a reference to any cert-manager Issuer or ClusterIssuer.

**Documentation:** See [modules/self-signed-cluster-issuer/README.md](./modules/self-signed-cluster-issuer/README.md)

---

### materialize-instance

Deploys a Materialize instance as a Kubernetes custom resource managed by the Materialize operator.

**Key Features:**
- Creates Materialize instance custom resource
- Configures metadata backend (PostgreSQL) connection
- Configures persist backend (object storage) connection
- Manages instance lifecycle (rollouts, upgrades)
- Configurable resource requests and limits
- Support for workload identity/IRSA annotations

**Requirements:**
- Materialize operator must be installed (via cloud-specific operator module)
- PostgreSQL database for metadata
- Object storage (S3/Azure Storage/GCS) for persistence
- cert-manager installed
- Certificate issuer (can be self-signed, Let's Encrypt, or any cert-manager compatible issuer)

**Documentation:** See [modules/materialize-instance/README.md](./modules/materialize-instance/README.md)

---

## Usage Pattern

These modules are typically used together in a specific order:

1. **cert-manager** - Install certificate management (required)
2. **Certificate Issuer** - Create or configure an issuer:
   - Use the provided **self-signed-cluster-issuer** module for quick setup, OR
   - Configure your own issuer (Let's Encrypt, organizational CA, etc.)
3. **materialize-instance** - Deploy Materialize instance with issuer reference

### Example Usage

```hcl
# 1. Install cert-manager
module "cert_manager" {
  source = "../kubernetes/modules/cert-manager"
  
  node_selector = {
    workload = "generic"
  }
}

# 2. Create self-signed issuer
module "self_signed_cluster_issuer" {
  source = "../kubernetes/modules/self-signed-cluster-issuer"
  
  name_prefix = "my-mz"
  
  depends_on = [module.cert_manager]
}

# 3. Deploy Materialize instance
module "materialize_instance" {
  source = "../kubernetes/modules/materialize-instance"
  
  instance_name        = "production"
  instance_namespace   = "materialize-environment"
  metadata_backend_url = "postgres://user:pass@host/db"
  persist_backend_url  = "s3://bucket-name/prefix"
  
  issuer_ref = {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }
  
  depends_on = [module.self_signed_cluster_issuer]
}
```

---

## Prerequisites

### Terraform Providers

All modules require the following Terraform providers:
- `kubernetes` >= 2.10.0
- `kubectl` >= 2.0 (for materialize-instance)
- `helm` >= 2.5.0 (for cert-manager)

### Kubernetes Cluster

- Kubernetes cluster version 1.24 or higher
- kubectl access configured
- Sufficient permissions to:
  - Create namespaces
  - Install Helm charts
  - Create custom resources
  - Create secrets

---

## Cloud-Specific Integration

While these modules are cloud-agnostic, they integrate with cloud-specific components:

### AWS
- **Service Account Annotations**: IRSA role ARN for S3 access
- **Example**: See [aws/examples/simple](../aws/examples/simple)

### Azure
- **Service Account Annotations**: Workload Identity client ID
- **Pod Labels**: Azure workload identity label
- **Example**: See [azure/examples/simple](../azure/examples/simple)

### GCP
- **Service Account Annotations**: GCP service account email (for future workload identity)
- **Current**: Uses HMAC keys for GCS access
- **Example**: See [gcp/examples/simple](../gcp/examples/simple)

---

## Security Considerations

### Certificates
- The self-signed issuer is suitable for internal communication and development
- For production external access, consider using Let's Encrypt or your organization's CA

### Secrets Management
- Metadata and persist backend URLs contain credentials
- These are stored as Kubernetes secrets
- Ensure RBAC policies restrict secret access
- Consider using external secret managers (AWS Secrets Manager, Azure Key Vault, etc.)

### Service Accounts
- Service accounts support cloud provider workload identity for passwordless authentication
- Configure appropriate IAM roles/policies for object storage access
- Avoid storing static credentials when workload identity is available

---

## Related Documentation

- [Materialize Self-Managed Documentation](https://materialize.com/docs/self-managed/v25.2/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
