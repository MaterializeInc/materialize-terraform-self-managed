# Example: Simple Materialize Deployment on an Existing Kubernetes Cluster

This example deploys self-managed Materialize onto a Kubernetes cluster you already have -- on-prem, bare-metal, a local [kind](https://kind.sigs.k8s.io/) cluster, or any managed cluster -- using only a kubeconfig. Unlike the `aws/`, `azure/`, and `gcp/` examples, it provisions no cloud infrastructure.

## What Gets Created

- **cert-manager** and a **self-signed ClusterIssuer** for TLS between Materialize components
- **Materialize operator** (`orchestratord`), installed from the [Helm chart](https://materializeinc.github.io/materialize/) into the `materialize` namespace, with the v1 CRD and its conversion webhook enabled
- **Materialize instance** (`main`) in the `materialize-environment` namespace, with password authentication for `mz_system`

## What You Bring

- A Kubernetes cluster and a kubeconfig that reaches it
- **Metadata backend**: a PostgreSQL database, passed as `metadata_backend_url`
- **Persist backend**: an S3-compatible object store (S3, RustFS, GCS interop, ...), passed as `persist_backend_url`
- A Materialize license key

The instance's clusters schedule onto nodes labeled `materialize.cloud/swap=true` by default (see the chart's `clusterd.swapNodeSelector`), so label the nodes Materialize should run on accordingly.

## Usage

```sh
terraform init
terraform apply \
  -var 'license_key=...' \
  -var 'metadata_backend_url=postgres://user:pass@postgres.example.com:5432/materialize' \
  -var 'persist_backend_url=s3://user:pass@bucket/prefix?endpoint=https%3A%2F%2Fs3.example.com&region=us-east-1'
```

Once applied, connect via the balancerd service (no load balancer is created):

```sh
kubectl port-forward -n "$(terraform output -raw materialize_instance_namespace)" "svc/$(terraform output -raw balancerd_service_name)" 6875:6875
PGPASSWORD="$(terraform output -raw external_login_password_mz_system)" \
  psql "sslmode=require host=127.0.0.1 port=6875 user=mz_system dbname=materialize"
```

This example is also what the test harness deploys onto a kind cluster for local/CI integration testing -- see `test/README.md`.
