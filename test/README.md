# Terraform Integration Tests

End-to-end integration tests for the Materialize self-managed Terraform modules. The test harness deploys real infrastructure on AWS, Azure, or GCP, verifies that Materialize is running, and tears it down. It can also run entirely locally against a [kind](https://kind.sigs.k8s.io/) cluster -- see [Local kind runs](#local-kind-runs-self-managed).

## Prerequisites

- Rust (edition 2024)
- Terraform >= 1.10
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

## Local kind runs (self-managed)

The `kind` provider runs the non-cloud-specific part of the test surface on your laptop, with no cloud credentials. It deploys `kubernetes/examples/simple` -- the customer-facing example for existing (non-cloud-managed) clusters -- onto a local kind cluster, with in-cluster PostgreSQL (metadata) and RustFS (persist) test backends from `test/kind/backends.yaml` standing in for the backends a customer would bring. This exercises the `kubernetes/` modules (`cert-manager`, `self-signed-cluster-issuer`, `materialize-instance`); the cloud-only modules (networking, managed clusters, load balancers, IAM, monitoring) are out of scope by construction and remain covered by the cloud providers.

Additional prerequisites: Docker, `kind`, `kubectl`.

```sh
cargo run -- run kind --owner "Your Name" --license-key-file /path/to/license.key
```

`init` creates a kind cluster named after the test run ID (so kind runs coexist with any other kind clusters and with each other), writes its kubeconfig into the test run directory, and deploys the test backends; `apply` deploys the example into it with terraform; `verify` runs the same checks as the cloud providers, except that the node-local-dns/CoreDNS checks are skipped (kind keeps its stock DNS) and SQL connectivity goes through a `kubectl port-forward` to balancerd instead of a load balancer; `destroy` deletes the kind cluster.

The staged workflow works as on the clouds, and is the fast path for iterating: keep the cluster up and re-run `verify` (or `sync` + `apply` after changing module code) without recreating anything:

```sh
cargo run -- init kind --owner "Your Name" --license-key-file key.txt
# => Test run initialized successfully: t260319-a4bc2f
cargo run -- apply --test-run t260319-a4bc2f
cargo run -- verify --test-run t260319-a4bc2f   # repeatable
cargo run -- destroy --test-run t260319-a4bc2f --rm
```

The dev overrides (`--local-chart-path`, `--orchestratord-version`, `--environmentd-version`) work with kind too, which makes it the cheapest way to smoke-test a local chart or new image version.

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

### `purge` -- Force-delete a run's AWS resources

A last-resort cleanup for when `terraform destroy` fails and leaks resources. AWS
has no single-container delete, so `purge` finds a run's resources by the unique
per-run id: most carry a `TestRun=<id>` tag (or, for controller-created resources,
the cluster tag, which embeds the id), while a few are matched by the `<id>` name
prefix (IAM instance profiles and policies, the Karpenter SQS queue and EventBridge
rules) or by membership in the run's tagged VPC (security groups, ENIs). It only
ever acts on resources tied to that long, unique run id, independent of terraform
state.

```sh
cargo run -- purge --test-run t260319-a4bc2f
```

A single invocation deletes resources in dependency order, waiting on the slow
deletions (EKS node groups and cluster, RDS instance, NAT gateways, load
balancers) before tearing down what they block, and repeats the whole sweep up to
five times (pausing 15s between passes) until nothing remains or no further
progress is made. So a normal run is fully reclaimed by one `purge`; only if
resources are still draining after five passes does it exit non-zero.
One exception: KMS keys cannot be deleted immediately, so the EKS encryption key
is scheduled for deletion with the 7-day minimum pending window rather than removed
outright. Some resource types are out of scope (see the module docs in
`src/commands/purge.rs`).

The AWS test workflow runs this automatically after every job.

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
| `--region` | GCP region (e.g. `us-east1`) |

### Azure

| Argument | Description |
|---|---|
| `--subscription-id` | Azure subscription ID |
| `--resource-group-name` | Azure resource group name |
| `--location` | Azure location (e.g. `westus2`) |

### Kind

No provider-specific arguments. Requires Docker and `kind` locally; the S3 backend options are accepted but unnecessary (state is small and local).

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

Reusable workflow, also manually triggerable (`workflow_dispatch`). Authenticates via OIDC to assume an IAM role, then runs the full test lifecycle (`cargo run -- run --destroy-on-failure aws ...`) with remote S3 state. Smart path filtering skips the run if only GCP/Azure files changed. An `always()` step then runs `cargo run -- purge` for any run whose destroy did not complete, guaranteeing tag-scoped cleanup of leaked resources regardless of job outcome.

### `test-gcp.yml` -- GCP integration tests

Same structure as AWS. Authenticates to GCP via Workload Identity Federation and to AWS via OIDC (for the S3 state backend). Skips if only AWS/Azure files changed.

### `test-azure.yml` -- Azure integration tests

Same structure as AWS. Authenticates to Azure via OIDC and to AWS via OIDC (for the S3 state backend). Skips if only AWS/GCP files changed.

### `test-kind.yml` -- Kind integration tests

Runs the self-managed kind lifecycle (`cargo run -- run --destroy-on-failure kind`) on a larger (`ubuntu-24.04-16core`) GitHub-hosted runner -- the stack's default resource requests do not fit the standard 4-CPU runner. Needs no cloud credentials, only the `MATERIALIZE_LICENSE_KEY` secret. Currently `workflow_dispatch`/`workflow_call` only -- not wired into the merge queue until it has proven reliable there.

All four test workflows use `--destroy-on-failure` to ensure infrastructure is torn down even on test failure; the three cloud workflows store Terraform state remotely in S3, while kind keeps state locally on the runner.

## Project layout

```
test/
  Cargo.toml
  README.md
  runs/              # test run directories (gitignored)
  kind/
    cluster.yaml     # kind cluster config (node labels for Materialize workloads)
    backends.yaml    # in-cluster PostgreSQL/RustFS test backends
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
