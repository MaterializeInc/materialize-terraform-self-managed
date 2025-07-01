# GCP Tests

This directory contains Terratest tests for GCP Materialize Terraform modules using staged deployment with dependency management.

## Testing Strategy

**Staged deployment approach:**
- Tests infrastructure deployment in stages with proper dependency management
- Supports reusing existing infrastructure across test runs
- Enables independent stage execution and cleanup

## Structure

```
gcp/
├── README.md                    # This file
├── go.mod                      # Go module for GCP tests
├── test_constants.go           # GCP-specific test constants
├── test_helpers.go             # Shared test utilities
├── staged_deployment_test.go   # Staged infrastructure deployment
├── debug.env                   # Environment configuration
└── testRuns/                   # Persistent state for test stages
    └── {uniqueId}/            # State directory per infrastructure family
        ├── network_name
        ├── network_id
        └── ...
```

## Prerequisites

### 1. Go Environment
- Go 1.23 or later
- Run `go mod tidy` to download dependencies

### 2. Google Cloud Setup
- A GCP project with the following APIs enabled:
  - Compute Engine API
  - Kubernetes Engine API
  - Cloud SQL Admin API
  - Cloud Storage API
  - Service Networking API
  - Cloud Resource Manager API
- Service account key or Application Default Credentials configured
- Set environment variable: `export GOOGLE_PROJECT=your-project-id`

### 3. Required Permissions
Your service account needs the following roles:
- `roles/compute.admin`
- `roles/container.admin`
- `roles/cloudsql.admin`
- `roles/storage.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/resourcemanager.projectIamAdmin`
- `roles/servicenetworking.networksAdmin`

### 4. Terraform
- Terraform 1.0 or later installed and in PATH

## Running Tests

### Install Dependencies
```bash
cd gcp
go mod tidy
```

### Set Environment Variables

The test suite automatically loads environment variables from these files (in order):
- `.env`
- `debug.env`
- `.env.debug`
- `.env.local`

You can also set them manually:
```bash
export GOOGLE_PROJECT=your-gcp-project-id
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json

# Stage control variables
export SKIP_setup_network=true
export SKIP_cleanup_database=true
```

### Running Tests

#### Full Test (Create network + database, cleanup both)
```bash
go test -timeout 30m -run TestStagedDeploymentSuite -v
```

#### Network Only (Skip database creation and network cleanup)
```bash
SKIP_setup_database=true SKIP_cleanup_network=true go test -timeout 15m -run TestStagedDeploymentSuite -v
```

#### Database on Existing Network (Skip network creation, keep network after)
```bash
SKIP_setup_network=true SKIP_cleanup_network=true go test -timeout 15m -run TestStagedDeploymentSuite -v
```

#### Cleanup Existing Infrastructure
```bash
SKIP_setup_network=true SKIP_setup_database=true go test -timeout 10m -run TestStagedDeploymentSuite -v
```

#### All Tests
```bash
go test -timeout 30m -v
```

## Test Features

### Test Stages
- **Stage-based execution** with `test_structure` package
- **Persistent state** across test runs in `testRuns/{uniqueId}/`
- **Dependency management** - database requires network to exist
- **Flexible cleanup** - control what gets cleaned up independently

### Infrastructure Families
- **Unique ID per family** - all related resources share same ID
- **State directory** - `testRuns/{uniqueId}/` contains all state
- **Auto-discovery** - finds existing infrastructure automatically
- **Complete cleanup** - removing network removes entire state directory AND all infrastructure

### Stage Control
Control test execution with environment variables (can be set in .env files):
- `SKIP_setup_network` - Skip network creation stage
- `SKIP_setup_database` - Skip database creation stage
- `SKIP_cleanup_network` - Skip network cleanup stage  
- `SKIP_cleanup_database` - Skip database cleanup stage

### Cleanup Behavior
- **Database cleanup**: Only removes database resources
- **Network cleanup**: Removes network resources AND deletes the entire state directory
- **State directory**: `testRuns/{uniqueId}/` is removed when network is cleaned up

### Resource Naming
All resources follow pattern: `test-{uniqueId}-{resource}`
- Network: `test-abc123-network`
- Database: `test-abc123-db`
- GKE: `test-abc123-gke` (future)

## Troubleshooting

### Common Issues
- **Timeout**: Use appropriate timeouts (network: 10m, database: 15m)
- **Missing network**: If you see "Cannot skip network creation", run without `SKIP_setup_network` first
- **State management**: Check `testRuns/` directory for existing infrastructure
- **Cleanup**: Network cleanup removes entire state directory and all resources
- **Environment variables**: Can be set in `.env`, `debug.env`, `.env.debug`, or `.env.local`
- **Permissions**: Ensure service account has required roles

### Manual Cleanup
```bash
# Check existing test infrastructure
ls -la test/gcp/testRuns/

# Run cleanup stages only
SKIP_setup_network=true SKIP_setup_database=true go test -timeout 10m -run TestStagedDeploymentSuite -v

# Manual cleanup if needed
cd gcp/examples/test-networking-basic
terraform destroy -auto-approve

cd ../test-database-basic
terraform destroy -auto-approve

# Remove state directory
rm -rf test/gcp/testRuns/{uniqueId}
```

## Links

- **GCP Examples**: [../../gcp/examples/](../../gcp/examples/)
- **Test Constants**: [test_constants.go](./test_constants.go)
- **Staged Deployment Test**: [staged_deployment_test.go](./staged_deployment_test.go)