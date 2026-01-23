# Contributing to materialize-terraform-self-managed

We love your input! We want to make contributing to materialize-terraform-self-managed as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## We Develop with Github
We use GitHub to host code, to track issues and feature requests, as well as accept pull requests.

## Pull Requests
Pull requests are the best way to propose changes to the codebase. We actively welcome your pull requests:

1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. If you've changed APIs, update the documentation.
4. Ensure the test suite passes.
5. Make sure your code lints.
6. Issue that pull request!


## Development Setup

This project uses [uv](https://docs.astral.sh/uv/) for Python dependency management. Install uv first:

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or with Homebrew
brew install uv
```

Then install the development dependencies:

```bash
uv sync
```

## Generating Documentation

This module uses [terraform-docs](https://terraform-docs.io/user-guide/introduction/) to generate documentation. To generate the documentation, run the following command from the root of the repository:

```bash
.github/scripts/generate-docs.sh
```

## Generating Terraform Type Definitions

The Terraform variable type definitions are auto-generated from the upstream Materialize CRD and Helm chart schemas. The version is read from the `environmentd_version` variable default in the source code.

To regenerate:

```bash
uv run python scripts/generate_terraform_types.py
```

### Checking Schema Sync

To verify that the generated Terraform types are in sync with upstream schemas:

```bash
uv run python scripts/check_schema_sync.py
```

This check runs automatically in CI via the `check-schema-sync` workflow.

## Development Process

1. Clone the repository
```bash
git clone https://github.com/MaterializeInc/materialize-terraform-self-managed.git
```

2. Create a new branch
```bash
git checkout -b feature/your-feature-name
```

3. Make your changes and test them:
```bash
# Access the cloud provider directory, eg aws, azure, etc.
cd aws  # or azure, gcp, etc.

# Format your code
terraform fmt -recursive

# Run linter
tflint

# Test the examples (optional - see Testing section below for integration tests)
cd <cloudDir>/examples/simple
terraform init
terraform plan
```

4. Commit your changes
```bash
git commit -m "Add your meaningful commit message"
```

5. Push to your fork and submit a pull request

## Testing

For comprehensive testing documentation including architecture, debugging tips, and cloud-specific details, see:
- [test/README.md](./test/README.md) - Testing overview and approach
- [test/aws/README.md](./test/aws/README.md) - AWS-specific testing
- [test/azure/README.md](./test/azure/README.md) - Azure-specific testing
- [test/gcp/README.md](./test/gcp/README.md) - GCP-specific testing

### Local Integration Tests (kind)

Python-based integration tests validate Terraform modules by deploying a full Materialize stack on a local kind cluster.

**Requirements:**
- Docker
- kind
- kubectl
- terraform
- helm
- `MATERIALIZE_LICENSE_KEY` environment variable

**Running the tests:**

```bash
# Set your license key
export MATERIALIZE_LICENSE_KEY="your-license-key"

# Run kind integration tests
uv run pytest tests/test_kind_integration.py -v --kind
```

The tests will:
1. Create a kind cluster
2. Deploy PostgreSQL and MinIO backends
3. Apply Terraform to install the Materialize operator and instance
4. Validate the deployment

**Note:** The kind cluster persists after tests for debugging. Delete manually with `kind delete cluster --name mz-test`.

### Contributing Tests

When adding new features or modules, please include corresponding tests:
1. **Add fixtures**: Create Terraform configurations in `fixtures/` directory
2. **Update test suite**: Modify `staged_deployment_test.go` to include new validation
3. **Update documentation**: Document new test scenarios in the cloud-specific README
4. **Run locally**: Ensure tests pass before submitting PR

## Versioning

We follow [Semantic Versioning](https://semver.org/). For version numbers:

- MAJOR version for incompatible API changes
- MINOR version for added functionality in a backwards compatible manner
- PATCH version for backwards compatible bug fixes

## Cutting a new release

Perform a manual test of the latest code on `main`. See prior section. Then run:

    git tag -a vX.Y.Z -m vX.Y.Z
    git push origin vX.Y.Z

## References

- [README.md](./README.md)
- [Terraform Documentation](https://www.terraform.io/docs)
