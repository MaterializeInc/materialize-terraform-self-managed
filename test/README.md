# Testing

This directory contains comprehensive integration tests for the Materialize Terraform modules using [Terratest](https://terratest.gruntwork.io/).

## Testing Approach

### Framework

We use **Terratest**, a Go library that provides patterns and helper functions for testing infrastructure code. Terratest allows us to:
- Deploy real infrastructure to cloud providers
- Validate that infrastructure works as expected
- Clean up resources after testing

**Learn More:**
- [Terratest Documentation](https://terratest.gruntwork.io/)
- [Terratest GitHub Repository](https://github.com/gruntwork-io/terratest)
- [Testing Terraform Best Practices](https://terratest.gruntwork.io/docs/testing-best-practices/unit-integration-end-to-end-test/)

### Staged Deployment Pattern

Our tests use a **staged deployment approach** that mirrors real-world infrastructure provisioning:

1. **Network Stage**: Deploy foundational networking (VPC/VNet, subnets, NAT gateways)
2. **Materialize Stage**: Deploy Materialize infrastructure (Kubernetes cluster, database, storage, Materialize instance)
3. **Validation**: Run tests against the deployed infrastructure
4. **Cleanup**: Destroy resources in reverse order

**Benefits:**
- **Realistic Testing**: Mimics how users actually deploy infrastructure
- **Efficient Resource Management**: Network can be reused across multiple test runs
- **Granular Control**: Each stage can be run independently for debugging
- **State Persistence**: Each test run maintains its own isolated state directory

### Test Structure

```
test/
├── aws/                    # AWS-specific tests
│   ├── fixtures/          # Terraform configurations for testing
│   ├── staged_deployment_test.go
│   └── README.md          # Detailed AWS testing instructions
├── azure/                  # Azure-specific tests
│   ├── fixtures/          # Terraform configurations for testing
│   ├── staged_deployment_test.go
│   └── README.md          # Detailed Azure testing instructions
├── gcp/                    # GCP-specific tests
│   ├── fixtures/          # Terraform configurations for testing
│   ├── staged_deployment_test.go
│   └── README.md          # Detailed GCP testing instructions
├── utils/                  # Shared testing utilities
│   ├── basesuite/         # Base test suite with common patterns
│   ├── helpers/           # Terraform and workspace helpers
│   ├── s3backend/         # S3 backend management
│   └── config/            # Configuration management
├── go.mod                  # Go module dependencies
└── go.sum                  # Go module checksums
```

## Prerequisites

### Common Requirements

- **Go**: Version 1.23 or higher
- **Terraform**: Version 1.0 or higher
- **Cloud Provider CLI**: aws-cli, az, or gcloud configured with appropriate credentials

### Cloud-Specific Requirements

Each cloud provider has specific prerequisites. See the detailed READMEs:
- [AWS Testing Prerequisites](./aws/README.md#prerequisites)
- [Azure Testing Prerequisites](./azure/README.md#prerequisites)
- [GCP Testing Prerequisites](./gcp/README.md#prerequisites)

## Test Coverage

Our test suites validate:
- **Network Infrastructure**: VPC/VNet creation, subnet configuration, NAT gateway functionality
- **Kubernetes Cluster**: Cluster creation, node pools, autoscaling
- **Database**: PostgreSQL instance connectivity and configuration
- **Storage**: Object storage bucket creation and access
- **Materialize Deployment**: Operator installation, instance creation, service accessibility
- **Integration**: TODO
