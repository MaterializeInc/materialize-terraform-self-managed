# Terraform Integration Tests

End-to-end integration tests for the Materialize self-managed Terraform modules. The test harness deploys real infrastructure on AWS, Azure, or GCP, verifies that Materialize is running, and tears it down.

## Prerequisites

- Rust (edition 2024)
- Terraform >= 1.8
- `psql` (PostgreSQL client)
- Cloud CLI for your provider:
  - **AWS**: `aws` CLI, configured profile
  - **GCP**: `gcloud` CLI, authenticated
  - **Azure**: `az` CLI, authenticated

## Quick start

Build the test binary:

```sh
cd test
cargo build
```

Run the full lifecycle (init, apply, verify, destroy) in one command:

```sh
cargo run -- run aws \
  --owner "Your Name" \
  --license-key-file /path/to/license.key \
  --aws-region us-east-1 \
  --aws-profile my-profile
```

## Commands

### `run` -- Full lifecycle

Runs init, apply, verify, and destroy in sequence. On success the test run directory is cleaned up automatically.

```sh
cargo run -- run <provider> [OPTIONS]
```

### `init` -- Create a test environment

Copies the example Terraform files, generates a `terraform.tfvars.json`, and runs `terraform init`. Prints a test run ID for use with subsequent commands.

```sh
cargo run -- init aws \
  --owner "Your Name" \
  --license-key-file /path/to/license.key \
  --aws-region us-east-1 \
  --aws-profile my-profile
```

### `apply` -- Deploy infrastructure

Runs `terraform apply` for an initialized test run.

```sh
cargo run -- apply --test-run t260319-a4bc2f
```

### `verify` -- Check deployment

Verifies the deployment by:
1. Configuring kubectl for the cluster
2. Waiting for the Materialize custom resource to be UpToDate
3. Waiting for all expected pods (environmentd, console, balancerd, clusterd) to be Running
4. Connecting to Materialize via SQL and running `SELECT 1`

```sh
cargo run -- verify --test-run t260319-a4bc2f
```

### `destroy` -- Tear down infrastructure

Runs `terraform destroy`. For AWS, automatically retries with ENI cleanup if the destroy gets stuck on orphaned network interfaces.

```sh
cargo run -- destroy --test-run t260319-a4bc2f
cargo run -- destroy --test-run t260319-a4bc2f --rm  # also delete the test run directory
```

### `list` -- Show test runs

Lists all test runs sorted by creation date.

```sh
cargo run -- list
cargo run -- list --latest  # print only the most recent
```

## Running individual phases

The staged approach is useful for development -- you can `init` and `apply` once, then iterate on `verify`, and `destroy` when done:

```sh
cargo run -- init aws --owner "Your Name" --license-key-file key.txt --aws-region us-east-1 --aws-profile my-profile
# => Test run initialized successfully: t260319-a4bc2f

cargo run -- apply --test-run t260319-a4bc2f
cargo run -- verify --test-run t260319-a4bc2f
cargo run -- destroy --test-run t260319-a4bc2f --rm
```

## License key

The Materialize license key can be provided in three ways (in order of precedence):

1. `--license-key <value>` -- inline on the command line
2. `--license-key-file <path>` -- read from a file
3. `MATERIALIZE_LICENSE_KEY` environment variable

## Provider-specific arguments

### AWS

| Argument | Description |
|---|---|
| `--aws-region` | AWS region (e.g. `us-east-1`) |
| `--aws-profile` | AWS CLI profile for authentication |

### GCP

| Argument | Description |
|---|---|
| `--project-id` | GCP project ID |
| `--region` | GCP region (e.g. `us-central1`) |

### Azure

| Argument | Description |
|---|---|
| `--subscription-id` | Azure subscription ID |
| `--resource-group-name` | Azure resource group name |
| `--location` | Azure location (e.g. `westus2`) |

## Common arguments

| Argument | Description | Default |
|---|---|---|
| `--owner` | Value for the Owner tag/label | (required) |
| `--purpose` | Value for the Purpose tag/label | `Integration test` |
| `--helm-chart` | Path to operator Helm chart | (optional) |
| `--use-local-chart` | Use local Helm chart | `false` |
| `--orchestratord-version` | Orchestratord image version | (optional) |
| `--environmentd-version` | Environmentd image version | (optional) |
| `--backend-s3-bucket` | S3 bucket for remote terraform state | (optional) |
| `--backend-s3-region` | S3 bucket region | `us-east-1` |
| `--backend-s3-profile` | AWS profile for S3 backend auth | (optional) |

## Remote state

By default, terraform state is stored locally in the test run directory. To store state remotely in S3, pass the `--backend-s3-bucket` option (works with any provider):

```sh
cargo run -- run aws \
  --owner "Your Name" \
  --license-key-file key.txt \
  --aws-region us-east-1 \
  --aws-profile my-profile \
  --backend-s3-bucket my-terraform-state-bucket \
  --backend-s3-region us-east-1 \
  --backend-s3-profile my-profile
```

If `--backend-s3-profile` is omitted, Terraform will use ambient AWS credentials (e.g. environment variables from OIDC).

The state key/prefix is automatically set to `{test-run-id}/terraform.tfstate`, keeping each test run's state isolated within the bucket.

## Test run directory

Test runs are stored under `test/runs/<id>/`. Each directory contains:

- Copied `.tf` files (with rewritten module paths)
- `terraform.tfvars.json` -- generated variables
- `.lifecycle` -- tracks the current phase and status (e.g. `apply completed`)
- `kubeconfig` -- generated during verify
- Terraform state and lock files

## GitHub Actions workflows

CI is split into six workflow files under `.github/workflows/`:

### `pr.yml` -- Pull request checks

Triggered on every pull request to `main`. Runs the lint workflow and gates the PR on a `ci-success` job that verifies all lint checks passed.

### `merge_queue.yml` -- Merge queue checks

Triggered when a PR enters GitHub's merge queue. Runs lint **and** the three provider test workflows (AWS, GCP, Azure) in parallel. The `ci-success` gate currently requires only lint to pass (provider tests are invoked but not yet blocking).

### `lint.yml` -- Lint and validate (reusable)

A reusable workflow (`workflow_call`) consumed by both `pr.yml` and `merge_queue.yml`. It runs three jobs:

- **Terraform Lint** -- `terraform fmt -check -recursive` and `tflint --recursive`
- **Validate Simple Examples** -- `terraform init -backend=false && terraform validate` for each example directory (`aws/examples/simple`, `azure/examples/simple`, `gcp/examples/simple`)
- **Rust Tests Lint** -- `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo deny check` on the test harness

### `test-aws.yml` -- AWS integration tests

Reusable workflow, also manually triggerable (`workflow_dispatch`). Authenticates via OIDC to assume an IAM role, then runs the full test lifecycle (`cargo run -- run --destroy-on-failure aws ...`) with remote S3 state. Smart path filtering skips the run if only GCP/Azure files changed.

### `test-gcp.yml` -- GCP integration tests

Same structure as AWS. Authenticates to GCP via Workload Identity Federation and to AWS via OIDC (for the S3 state backend). Skips if only AWS/Azure files changed.

### `test-azure.yml` -- Azure integration tests

Same structure as AWS. Authenticates to Azure via OIDC and to AWS via OIDC (for the S3 state backend). Skips if only AWS/GCP files changed.

All three provider test workflows use `--destroy-on-failure` to ensure infrastructure is torn down even on test failure, and store Terraform state remotely in S3.

## Project layout

```
test/
  Cargo.toml
  README.md
  runs/              # test run directories (gitignored)
  src/
    main.rs          # CLI dispatch
    cli.rs           # argument definitions
    types.rs         # CloudProvider, TfVars, TerraformOutputs
    helpers.rs       # command execution, retry, lifecycle, ID generation
    commands/
      mod.rs         # re-exports
      init.rs        # phase_init
      apply.rs       # phase_apply
      verify.rs      # phase_verify
      destroy.rs     # phase_destroy
      list.rs        # list command
```
