# GCP Tests

Terratest tests for GCP Materialize Terraform modules using staged deployment.

## Test Architecture

**Staged Deployment Pattern:**
- **Network Stage**: VPC, subnets, NAT gateway
- **Materialize Stage**: GKE, CloudSQL, GCS, Materialize instance
- **State Management**: Each test run creates `{uniqueId}/` directory with persistent state
- **Dependency Management**: Materialize stage requires network to exist

**Resource Naming Convention:**
- Pattern: `{shortUniqueId}-{resource}`
- Examples: `abc123-vpc`, `abc123-gke`, `abc123-db`

## Prerequisites

- Go 1.23+, Terraform 1.0+
- GCP project with required APIs enabled
- Service account with roles: `compute.admin`, `container.admin`, `cloudsql.admin`, `storage.admin`, `iam.serviceAccountAdmin`
- Set `GOOGLE_PROJECT=your-project-id`

## Running Tests

```bash
# Install dependencies
cd test && go mod tidy

# Full test (network + materialize + cleanup)
cd test/gcp
go test -timeout 135m -run TestStagedDeploymentSuite -v

# Network only
SKIP_setup_materialize_disk_enabled=true SKIP_setup_materialize_disk_disabled=true SKIP_cleanup_network=true go test -timeout 30m -run TestStagedDeploymentSuite -v

# Materialize on existing network
SKIP_setup_network=true SKIP_cleanup_network=true go test -timeout 90m -run TestStagedDeploymentSuite -v

# Cleanup only
SKIP_setup_network=true SKIP_setup_materialize_disk_enabled=true SKIP_setup_materialize_disk_disabled=true go test -timeout 90m -run TestStagedDeploymentSuite -v
```

## Stage Control

Control execution with environment variables:
- `SKIP_setup_network` - Skip network creation
- `SKIP_setup_materialize_disk_enabled` - Skip disk-enabled materialize
- `SKIP_setup_materialize_disk_disabled` - Skip disk-disabled materialize
- `SKIP_cleanup_network` - Skip network cleanup
- `SKIP_cleanup_materialize_disk_enabled` - Skip disk-enabled cleanup
- `SKIP_cleanup_materialize_disk_disabled` - Skip disk-disabled cleanup

## Debugging & Manual Cleanup

**Test-Generated tfvars Files:**
Tests create `terraform.tfvars.json` files in each fixture directory (`{uniqueId}/networking/`, `{uniqueId}/materialize/`), making manual debugging convenient.

**Manual Cleanup:**
```bash
# Check existing infrastructure
ls -la test/gcp/

# Manual terraform operations
cd test/gcp/{uniqueId}/{fixtureDirectory}
terraform plan    # Review changes
terraform apply   # Apply changes
terraform destroy # Cleanup resources

# Remove state directory
rm -rf test/gcp/{uniqueId}
```

**Environment Variables:**
- Loaded from `local.env` (if exists) or `.env`
- Can be set manually: `export GOOGLE_PROJECT=your-project-id`

## Troubleshooting

- **Timeouts**: Network (15m), Materialize (60m), Full (90m)
- **Missing network**: Run without `SKIP_setup_network` first
- **State issues**: Check `{uniqueId}/` directories
- **Cleanup**: Network cleanup removes entire state directory and all resources
