# Materialize Infrastructure Modules

Terraform modules for deploying Materialize across different cloud providers. You can use these modules individually or combine them to build your infrastructure stack.

The repository splits into two main parts: cloud-specific infrastructure modules and cloud-agnostic Kubernetes modules. This separation lets you mix and match components based on your needs.

```
├── aws/                    # AWS infrastructure (VPC, EKS, RDS, S3)
│   └── examples/          # AWS deployment examples
├── kubernetes/             # Kubernetes apps (cert-manager, storage, Materialize)
```

## Getting Started

You'll need Terraform installed and credentials configured for your cloud provider. The modules work independently, so you can start with just the pieces you need.

### Deploy AWS Infrastructure

Example project:

* [`aws/examples/simple`](./aws/examples/simple)

---

## Local Development & Linting

Run this to format and generate docs across all modules:

```bash
.github/scripts/generate-docs.sh
```

Make sure `terraform-docs` and `tflint` are installed locally.
