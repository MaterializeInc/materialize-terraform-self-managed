use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::{Args as ClapArgs, Parser, Subcommand};

use crate::types::CloudProvider;

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
}

impl InitProvider {
    pub fn cloud_provider(&self) -> CloudProvider {
        match self {
            InitProvider::Aws { .. } => CloudProvider::Aws,
            InitProvider::Azure { .. } => CloudProvider::Azure,
            InitProvider::Gcp { .. } => CloudProvider::Gcp,
        }
    }

    pub fn common(&self) -> &CommonInitArgs {
        match self {
            InitProvider::Aws { common, .. }
            | InitProvider::Azure { common, .. }
            | InitProvider::Gcp { common, .. } => common,
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
