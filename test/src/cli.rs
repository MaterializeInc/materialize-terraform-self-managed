use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::{Args as ClapArgs, Parser, Subcommand, ValueEnum};

use crate::types::CloudProvider;

/// Which object store backs persist.
#[derive(Copy, Clone, Debug, PartialEq, Eq, ValueEnum)]
pub enum PersistBackend {
    /// Whatever the example provisions, which is the cloud's object storage.
    Default,
    /// RustFS, deployed into the cluster as a StatefulSet.
    Rustfs,
    /// Ceph, deployed into the cluster by the Rook operator.
    Ceph,
}

/// Shape of the benchmark matrix.
#[derive(ClapArgs, Debug, Clone)]
pub struct BenchmarkArgs {
    /// Object sizes to measure, in bytes.
    ///
    /// The defaults bracket persist's own shape: batch parts from a few
    /// hundred KiB up to a 128 MiB target, uploaded in 8 MiB multipart pieces,
    /// so the last two sizes cross the multipart threshold.
    #[arg(long, default_value = "4096,65536,1048576,8388608,67108864")]
    pub sizes: String,
    /// Operations in flight.
    #[arg(long, default_value_t = 32)]
    pub concurrency: u32,
    /// Bytes written per cell, which sets how many objects each size writes.
    #[arg(long, default_value_t = 268435456)]
    pub bytes_per_cell: u64,
    /// Ceiling on objects per cell, so small sizes stay bounded.
    #[arg(long, default_value_t = 4096)]
    pub max_objects: u64,
    /// Seconds spent reading in each cell.
    #[arg(long, default_value_t = 10)]
    pub read_secs: u32,
    /// Image providing `persistcli`, which drives the store through persist's
    /// own S3 client.
    ///
    /// Required, with no default on purpose. `persistcli` ships only in
    /// `materialize/jobs`, which publishes no stable release tag, and whose
    /// `mzbuild-*` tags are single-architecture: a tag that works on amd64
    /// will not pull on arm64, and vice versa. A wrong default would surface
    /// as an ImagePullBackOff well into a run rather than immediately. Pick a
    /// tag matching the node architecture from
    /// <https://hub.docker.com/r/materialize/jobs/tags>.
    #[arg(long)]
    pub image: String,
    /// Store to measure, overriding the in-cluster one this run was built
    /// with.
    ///
    /// The form `persistcli bench blob` takes, for example
    /// `s3://bucket/prefix?region=us-east-1`. This is how a cloud provider's
    /// own object store is measured from the same cluster and the same nodes
    /// as the in-cluster stores, which is what makes the numbers comparable.
    #[arg(long)]
    pub blob_uri: Option<String>,
    /// Service account the benchmark Job runs as.
    ///
    /// A cloud object store authenticates by identity rather than by keys in
    /// the URL, and the identity is bound to one service account in one
    /// namespace, so measuring one means borrowing the account persist itself
    /// uses, together with `--namespace`.
    #[arg(long)]
    pub service_account: Option<String>,
    /// Namespace the benchmark Job runs in, overriding the store's own.
    #[arg(long)]
    pub namespace: Option<String>,
    /// Seconds to wait for the whole matrix.
    #[arg(long, default_value_t = 7200)]
    pub timeout_secs: u64,
    /// Skip the blob-level benchmark.
    #[arg(long)]
    pub skip_blob: bool,
    /// Skip the SQL-level benchmark.
    #[arg(long)]
    pub skip_sql: bool,
}

impl PersistBackend {
    /// The `kubernetes/modules` directory holding this backend's module, or
    /// `None` when the example's own object storage is used.
    pub fn module_name(self) -> Option<&'static str> {
        match self {
            PersistBackend::Default => None,
            PersistBackend::Rustfs => Some("object-store-rustfs"),
            PersistBackend::Ceph => Some("object-store-rook-ceph"),
        }
    }
}

#[derive(Parser, Debug)]
pub struct Args {
    #[clap(subcommand)]
    pub command: SubCommand,
}

#[derive(Subcommand, Debug)]
pub enum SubCommand {
    /// Copies the example terraform code to a subdirectory,
    /// creates a new terraform.tfvars.json, and runs `terraform init`.
    Init {
        #[clap(subcommand)]
        provider: Box<InitProvider>,
    },
    /// Runs `terraform apply` for an already initialized test environment.
    Apply {
        /// Which test run to apply.
        #[arg(long)]
        test_run: String,
    },
    /// Runs verification commands against an already applied test environment.
    Verify {
        /// Which test run to verify.
        #[arg(long)]
        test_run: String,
    },
    /// Measures the object store backing persist, against an already applied
    /// test environment.
    ///
    /// Deliberately outside `run`: it holds the environment for as long as the
    /// matrix takes and produces numbers rather than a pass or fail.
    Benchmark {
        /// Which test run to benchmark.
        #[arg(long)]
        test_run: String,
        #[clap(flatten)]
        args: BenchmarkArgs,
    },
    /// Lists test runs, sorted by creation date.
    List {
        /// Only print the most recent test run.
        #[arg(long)]
        latest: bool,
    },
    /// Re-copies example .tf files into an already initialized test run,
    /// picking up any local changes to the terraform code.
    Sync {
        /// Which test run to sync.
        #[arg(long)]
        test_run: String,
    },
    /// Runs `terraform destroy` against an already initialized test environment.
    Destroy {
        /// Which test run to destroy.
        #[arg(long)]
        test_run: String,
        /// Remove the test run directory after successful destroy.
        #[arg(long)]
        rm: bool,
    },
    /// Deletes every AWS resource tagged for a test run, independent of
    /// terraform state. A last-resort cleanup for when `terraform destroy`
    /// fails and leaks resources. Scoped strictly to the run's `TestRun` tag.
    Purge {
        /// Which test run to purge.
        #[arg(long)]
        test_run: String,
    },
    /// Runs the full test lifecycle: init, apply, verify, destroy.
    Run {
        #[clap(subcommand)]
        provider: Box<InitProvider>,
        /// Run `terraform destroy` even if apply or verify fails.
        #[arg(long)]
        destroy_on_failure: bool,
    },
}

#[derive(ClapArgs, Debug)]
pub struct CommonInitArgs {
    /// Value for the Owner tag/label applied to all resources.
    #[arg(long)]
    pub owner: String,
    /// Value for the Purpose tag/label applied to all resources.
    #[arg(long, default_value = "Integration test")]
    pub purpose: String,
    /// Value for the `reason` tag required by the scratch account SCP (AWS only).
    #[arg(
        long,
        default_value = "materialize-terraform-self-managed integration test"
    )]
    pub reason: String,
    /// Value for the `team` tag required by the scratch account SCP (AWS only).
    #[arg(long, default_value = "cloud")]
    pub team: String,
    /// Hours from now used to compute the `After` tag required.
    #[arg(long, default_value_t = 96)]
    pub delete_after_hours: i64,
    /// Materialize license key (conflicts with --license-key-file).
    #[arg(
        long,
        env = "MATERIALIZE_LICENSE_KEY",
        hide_env_values = true,
        conflicts_with = "license_key_file",
        required_unless_present = "license_key_file"
    )]
    pub license_key: Option<String>,
    /// Path to a file containing the Materialize license key (conflicts with --license-key).
    #[arg(long, conflicts_with = "license_key")]
    pub license_key_file: Option<PathBuf>,
    /// Path to a local orchestratord Helm chart directory. When set, automatically
    /// injects helm_chart / use_local_chart into the operator module, creates
    /// dev_variables.tf, and sets the corresponding tfvars values.
    #[arg(long)]
    pub local_chart_path: Option<PathBuf>,
    /// Orchestratord image version.
    #[arg(long)]
    pub orchestratord_version: Option<String>,
    /// Environmentd image version.
    #[arg(long)]
    pub environmentd_version: Option<String>,
    /// Object store to back persist with.
    ///
    /// The default leaves the example alone, so persist uses whatever object
    /// storage that example provisions. The other values deploy an
    /// S3-compatible store into the cluster and point Materialize at that
    /// instead, which is what makes two stores comparable on identical
    /// hardware. The example's own bucket is still created and goes unused.
    #[arg(long, value_enum, default_value_t = PersistBackend::Default)]
    pub persist_backend: PersistBackend,
    /// S3 bucket for remote terraform state. If omitted, state is stored locally.
    #[arg(long)]
    pub backend_s3_bucket: Option<String>,
    /// S3 region for the remote terraform state bucket. Required when --backend-s3-bucket is set.
    #[arg(long, default_value = "us-east-1")]
    pub backend_s3_region: String,
    /// AWS profile for S3 backend authentication.
    #[arg(long)]
    pub backend_s3_profile: Option<String>,
}

/// Configuration for an S3 remote backend.
pub struct S3BackendConfig<'a> {
    pub bucket: &'a str,
    pub region: &'a str,
    pub profile: Option<&'a str>,
}

impl CommonInitArgs {
    /// Resolves the license key from either `--license-key` or `--license-key-file`.
    pub fn resolve_license_key(&self) -> Result<String> {
        if let Some(key) = &self.license_key {
            return Ok(key.clone());
        }
        if let Some(path) = &self.license_key_file {
            let content = std::fs::read_to_string(path)
                .with_context(|| format!("Failed to read license key file: {}", path.display()))?;
            return Ok(content.trim().to_string());
        }
        bail!("Either --license-key or --license-key-file must be provided")
    }

    /// Returns the S3 backend configuration if `--backend-s3-bucket` is set.
    pub fn s3_backend(&self) -> Option<S3BackendConfig<'_>> {
        let bucket = self.backend_s3_bucket.as_deref()?;
        Some(S3BackendConfig {
            bucket,
            region: &self.backend_s3_region,
            profile: self.backend_s3_profile.as_deref(),
        })
    }
}

#[derive(Subcommand, Debug)]
pub enum InitProvider {
    /// Initialize a test run on AWS.
    Aws {
        #[clap(flatten)]
        common: CommonInitArgs,
        /// AWS region.
        #[arg(long)]
        aws_region: String,
        /// AWS profile for authentication.
        #[arg(long)]
        aws_profile: String,
    },
    /// Initialize a test run on Azure.
    Azure {
        #[clap(flatten)]
        common: CommonInitArgs,
        /// Azure subscription ID.
        #[arg(long)]
        subscription_id: String,
        /// Azure resource group name. Defaults to the test run ID if omitted.
        #[arg(long)]
        resource_group_name: Option<String>,
        /// Azure location.
        #[arg(long)]
        location: String,
    },
    /// Initialize a test run on GCP.
    Gcp {
        #[clap(flatten)]
        common: CommonInitArgs,
        /// GCP project ID.
        #[arg(long)]
        project_id: String,
        /// GCP region.
        #[arg(long)]
        region: String,
    },
    /// Initialize a self-managed test run on a local kind cluster.
    Kind {
        #[clap(flatten)]
        common: CommonInitArgs,
    },
}

impl InitProvider {
    pub fn cloud_provider(&self) -> CloudProvider {
        match self {
            InitProvider::Aws { .. } => CloudProvider::Aws,
            InitProvider::Azure { .. } => CloudProvider::Azure,
            InitProvider::Gcp { .. } => CloudProvider::Gcp,
            InitProvider::Kind { .. } => CloudProvider::Kind,
        }
    }

    pub fn common(&self) -> &CommonInitArgs {
        match self {
            InitProvider::Aws { common, .. }
            | InitProvider::Azure { common, .. }
            | InitProvider::Gcp { common, .. }
            | InitProvider::Kind { common } => common,
        }
    }

    /// Returns the content for a `backend.tf` file if an S3 backend is
    /// configured via `--backend-s3-bucket`, or `None` for local state.
    pub fn backend_config(&self, test_run_id: &str) -> Option<String> {
        let cfg = self.common().s3_backend()?;
        let bucket = cfg.bucket;
        let region = cfg.region;
        let profile_line = cfg
            .profile
            .map(|p| format!("\n    profile = \"{p}\""))
            .unwrap_or_default();
        Some(format!(
            r#"terraform {{
  backend "s3" {{
    bucket  = "{bucket}"
    key     = "{test_run_id}/terraform.tfstate"
    region  = "{region}"{profile_line}
  }}
}}
"#
        ))
    }
}
