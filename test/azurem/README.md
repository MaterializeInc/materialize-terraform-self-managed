# Azure Tests

This directory contains Terratest tests for Azure Materialize Terraform modules using staged deployment with dependency management, following the AWS test pattern.

## Testing Strategy

**Staged deployment approach:**
- Tests infrastructure deployment in stages with proper dependency management
- Supports reusing existing infrastructure across test runs
- Enables independent stage execution and cleanup
- Uses workspace copying pattern for test isolation

## Structure

```
azure/
├── README.md                    # This file
├── test_constants.go           # Azure-specific test constants
├── test_helpers.go             # Shared test utilities
├── staged_deployment_test.go   # Staged infrastructure deployment
├── local.env                   # Environment configuration
└── testRuns/                   # Persistent state for test stages
    └── {uniqueId}/            # State directory per infrastructure family
        ├── resource_group_name
        ├── vnet_name
        └── ...
```

## Prerequisites

### 1. Go Environment
- Go 1.23 or later
- Run `go mod tidy` in the parent test directory to download dependencies

### 2. Azure Setup
- An Azure subscription with the following services available:
  - Virtual Networks
  - Azure Kubernetes Service (AKS)
  - Azure Database for PostgreSQL - Flexible Server
  - Azure Storage Accounts
  - Azure NAT Gateway
  - Azure Private DNS
- Service Principal or Azure CLI authentication configured
- Set environment variables for authentication

### 3. Required Permissions
Your service principal needs the following roles:
- `Contributor` role on the subscription or resource group
- `User Access Administrator` role (for role assignments)

### 4. Terraform
- Terraform 1.0 or later installed and in PATH

## Running Tests

### Install Dependencies
```bash
cd test
go mod tidy
```

### Set Environment Variables

The test suite automatically loads environment variables from these files.
- `local.env` (if this file exists, load configuration and exit)
- `.env` (if `local.env` doesn't exist then try to load from `.env` file)


You can also set them manually:
```bash
export ARM_SUBSCRIPTION_ID=your-azure-subscription-id
export TEST_REGION=westus2

# Stage control variables
export SKIP_setup_network=true
export SKIP_cleanup_aks_disk_enabled=true
```

**Note:** Only `ARM_SUBSCRIPTION_ID` is required. The test uses Azure CLI or managed identity for authentication.

### Running Tests

#### Full Test (Create network + database + AKS + Materialize, cleanup all)
```bash
cd test/azure
go test -timeout 45m -run TestStagedDeploymentTestSuite -v
```

#### Network Only (Skip other stages and network cleanup)
```bash
SKIP_setup_aks_disk_enabled=true SKIP_setup_database_disk_enabled=true SKIP_setup_materialize_disk_enabled=true SKIP_cleanup_network=true go test -timeout 15m -run TestStagedDeploymentTestSuite -v
```

#### Database on Existing Network (Skip network creation, keep network after)
```bash
SKIP_setup_network=true SKIP_cleanup_network=true go test -timeout 20m -run TestStagedDeploymentTestSuite -v
```

#### Cleanup Existing Infrastructure
```bash
SKIP_setup_network=true SKIP_setup_aks_disk_enabled=true SKIP_setup_database_disk_enabled=true SKIP_setup_materialize_disk_enabled=true go test -timeout 15m -run TestStagedDeploymentTestSuite -v
```

#### All Tests
```bash
go test -timeout 45m -v
```

## Test Features

### Test Stages
- **Stage-based execution** with `test_structure` package
- **Persistent state** across test runs in `testRuns/{uniqueId}/`
- **Dependency management** - database and AKS require network to exist
- **Flexible cleanup** - control what gets cleaned up independently

### Infrastructure Families
- **Unique ID per family** - all related resources share same ID
- **State directory** - `testRuns/{uniqueId}/` contains all state
- **Auto-discovery** - finds existing infrastructure automatically
- **Complete cleanup** - removing network removes entire state directory AND all infrastructure

### Stage Control
Control test execution with environment variables (can be set in .env files):
- `SKIP_setup_network` - Skip network creation stage
- `SKIP_setup_aks_disk_enabled` - Skip AKS creation stage (disk-enabled)
- `SKIP_setup_database_disk_enabled` - Skip database creation stage (disk-enabled)
- `SKIP_setup_materialize_disk_enabled` - Skip Materialize installation stage (disk-enabled)
- `SKIP_cleanup_network` - Skip network cleanup stage  
- `SKIP_cleanup_aks_disk_enabled` - Skip AKS cleanup stage (disk-enabled)
- `SKIP_cleanup_database_disk_enabled` - Skip database cleanup stage (disk-enabled)
- `SKIP_cleanup_materialize_disk_enabled` - Skip Materialize cleanup stage (disk-enabled)

### Cleanup Behavior
- **Materialize cleanup**: Only removes Materialize resources
- **AKS cleanup**: Only removes AKS cluster and node pools
- **Database cleanup**: Only removes database resources
- **Network cleanup**: Removes network resources AND deletes the entire state directory
- **State directory**: `testRuns/{uniqueId}/` is removed when network is cleaned up

### Resource Naming
All resources follow pattern: `test-{shortUniqueId}-{resource}`
- Resource Group: `test-abc123-rg`
- Network: `test-abc123-vnet`
- Database: `test-abc123-db`
- AKS: `test-abc123-aks`

## Test Examples

The tests use dedicated example configurations in `azurem/examples/`:
- `test-networking/` - Network infrastructure only
- `test-database/` - PostgreSQL database only
- `test-aks/` - AKS cluster with node pools
- `test-materialize/` - Materialize operator and instance


## Troubleshooting

### Common Issues
- **Timeout**: Use appropriate timeouts (network: 15m, database: 20m, AKS: 30m, full: 45m)
- **Missing network**: If you see "Cannot skip network creation", run without `SKIP_setup_network` first
- **State management**: Check `testRuns/` directory for existing infrastructure
- **Cleanup**: Network cleanup removes entire state directory and all resources
- **Environment variables**: Can be set in `.env`, `local.env`, `.env.debug`, or `.env.local`
- **Permissions**: Ensure service principal has required roles
- **Azure quotas**: Ensure subscription has sufficient quota for VM sizes and regions

### Manual Cleanup
```bash
# Check existing test infrastructure
ls -la test/azure/testRuns/

# Run cleanup stages only
SKIP_setup_network=true SKIP_setup_database=true SKIP_setup_aks=true go test -timeout 15m -run TestStagedDeploymentTestSuite -v

# Manual cleanup if needed
cd azurem/examples/test-networking-basic
terraform destroy -auto-approve

cd ../test-database-basic
terraform destroy -auto-approve

cd ../test-aks-basic
terraform destroy -auto-approve

# Remove state directory
rm -rf test/azure/testRuns/{uniqueId}
```

## Azure-Specific Considerations

### Resource Naming
- Azure has different naming conventions and length limits per resource type
- Resource group names must be unique within subscription
- AKS cluster names must be unique within resource group

### Networking
- Uses Azure Virtual Network (VNet) with subnets for AKS and PostgreSQL
- NAT Gateway for outbound connectivity
- Private DNS zones for internal name resolution

### Database
- Uses Azure Database for PostgreSQL - Flexible Server
- Private endpoint for secure connectivity
- Automatic backup and point-in-time recovery

### AKS
- System node pool for Kubernetes system components
- Separate user node pool for Materialize workloads
- Workload Identity for secure pod-to-Azure service authentication

## Links

- **Azure Examples**: [../../azurem/examples/](../../azurem/examples/)
- **Test Constants**: [test_constants.go](./test_constants.go)
- **Staged Deployment Test**: [staged_deployment_test.go](./staged_deployment_test.go)

