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
    /// Path to Helm chart for the operator.
    #[arg(long)]
    pub helm_chart: Option<String>,
    /// Use a local Helm chart instead of a registry chart.
    #[arg(long)]
    pub use_local_chart: bool,
    /// Orchestratord image version.
    #[arg(long)]
    pub orchestratord_version: Option<String>,
    /// Environmentd image version.
    #[arg(long)]
    pub environmentd_version: Option<String>,
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
        /// S3 bucket for remote terraform state. If omitted, state is stored locally.
        #[arg(long)]
        backend_bucket: Option<String>,
    },
    /// Initialize a test run on Azure.
    Azure {
        #[clap(flatten)]
        common: CommonInitArgs,
        /// Azure subscription ID.
        #[arg(long)]
        subscription_id: String,
        /// Azure resource group name.
        #[arg(long)]
        resource_group_name: String,
        /// Azure location.
        #[arg(long)]
        location: String,
        /// Azure storage account name for remote terraform state.
        #[arg(long)]
        backend_storage_account: Option<String>,
        /// Azure storage container name for remote terraform state.
        #[arg(long, default_value = "tfstate")]
        backend_container: String,
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
        /// GCS bucket for remote terraform state. If omitted, state is stored locally.
        #[arg(long)]
        backend_bucket: Option<String>,
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

    /// Returns the content for a `backend.tf` file if remote state is
    /// configured, or `None` for local state.
    pub fn backend_config(&self, test_run_id: &str) -> Option<String> {
        match self {
            InitProvider::Aws {
                backend_bucket: Some(bucket),
                aws_region,
                aws_profile,
                ..
            } => Some(format!(
                r#"terraform {{
  backend "s3" {{
    bucket  = "{bucket}"
    key     = "{test_run_id}/terraform.tfstate"
    region  = "{aws_region}"
    profile = "{aws_profile}"
  }}
}}
"#
            )),
            InitProvider::Azure {
                backend_storage_account: Some(account),
                backend_container,
                resource_group_name,
                ..
            } => Some(format!(
                r#"terraform {{
  backend "azurerm" {{
    resource_group_name  = "{resource_group_name}"
    storage_account_name = "{account}"
    container_name       = "{backend_container}"
    key                  = "{test_run_id}/terraform.tfstate"
  }}
}}
"#
            )),
            InitProvider::Gcp {
                backend_bucket: Some(bucket),
                ..
            } => Some(format!(
                r#"terraform {{
  backend "gcs" {{
    bucket = "{bucket}"
    prefix = "{test_run_id}"
  }}
}}
"#
            )),
            _ => None,
        }
    }
}
