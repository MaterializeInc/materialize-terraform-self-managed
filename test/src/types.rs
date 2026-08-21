use std::collections::HashMap;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Cloud provider
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CloudProvider {
    Aws,
    Azure,
    Gcp,
    /// A local kind cluster running the self-managed configuration. Not a
    /// cloud: no cloud credentials, load balancers, or managed backends.
    Kind,
}

impl CloudProvider {
    pub fn dir_name(self) -> &'static str {
        match self {
            CloudProvider::Aws => "aws",
            CloudProvider::Azure => "azure",
            CloudProvider::Gcp => "gcp",
            // kind deploys the cloud-independent kubernetes/ example.
            CloudProvider::Kind => "kubernetes",
        }
    }
}

// ---------------------------------------------------------------------------
// terraform.tfvars.json – written during init, read back during verify
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CommonTfVars {
    pub name_prefix: String,
    pub license_key: String,
    /// Cloud-only; `None` (omitted) for kind, which has no load balancers.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub internal_load_balancer: Option<bool>,
    /// The test clusters are ephemeral and the runner needs a public address to
    /// reach Materialize, which means `0.0.0.0/0` on a public load balancer. The
    /// monitoring module refuses that for Grafana specifically, so the test roots
    /// acknowledge it here. The examples leave it `false`. Cloud-only; `None`
    /// (omitted) for kind.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grafana_allow_public_access: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub helm_chart: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub use_local_chart: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub orchestratord_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub environmentd_version: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "cloud_provider")]
pub enum TfVars {
    #[serde(rename = "aws")]
    Aws {
        #[serde(flatten)]
        common: CommonTfVars,
        aws_region: String,
        aws_profile: String,
        tags: HashMap<String, String>,
    },
    #[serde(rename = "azure")]
    Azure {
        #[serde(flatten)]
        common: CommonTfVars,
        subscription_id: String,
        resource_group_name: String,
        location: String,
        tags: HashMap<String, String>,
    },
    #[serde(rename = "gcp")]
    Gcp {
        #[serde(flatten)]
        common: CommonTfVars,
        project_id: String,
        region: String,
        labels: HashMap<String, String>,
    },
    #[serde(rename = "kind")]
    Kind {
        #[serde(flatten)]
        common: CommonTfVars,
        /// Relative to the run directory, where init writes it.
        kubeconfig_path: String,
        /// The in-cluster backends from test/kind/backends.yaml.
        metadata_backend_url: String,
        persist_backend_url: String,
    },
}

impl TfVars {
    pub fn cloud_provider(&self) -> CloudProvider {
        match self {
            TfVars::Aws { .. } => CloudProvider::Aws,
            TfVars::Azure { .. } => CloudProvider::Azure,
            TfVars::Gcp { .. } => CloudProvider::Gcp,
            TfVars::Kind { .. } => CloudProvider::Kind,
        }
    }

    pub fn common(&self) -> &CommonTfVars {
        match self {
            TfVars::Aws { common, .. }
            | TfVars::Azure { common, .. }
            | TfVars::Gcp { common, .. }
            | TfVars::Kind { common, .. } => common,
        }
    }

    pub fn common_mut(&mut self) -> &mut CommonTfVars {
        match self {
            TfVars::Aws { common, .. }
            | TfVars::Azure { common, .. }
            | TfVars::Gcp { common, .. }
            | TfVars::Kind { common, .. } => common,
        }
    }
}

// ---------------------------------------------------------------------------
// terraform output -json
// ---------------------------------------------------------------------------

/// Wrapper for terraform's output JSON format: `{"value": T, "type": ..., "sensitive": ...}`.
#[derive(Debug, Deserialize)]
pub struct TfOutput<T> {
    pub value: T,
}

#[derive(Debug, Deserialize)]
pub struct TerraformOutputs {
    pub materialize_instance_name: TfOutput<String>,
    pub materialize_instance_namespace: TfOutput<String>,

    #[serde(default)]
    pub eks_cluster_name: Option<TfOutput<String>>,
    #[serde(default)]
    pub gke_cluster_name: Option<TfOutput<String>>,
    #[serde(default)]
    pub aks_cluster_name: Option<TfOutput<String>>,

    #[serde(default)]
    pub nlb_dns_name: Option<TfOutput<String>>,
    #[serde(default)]
    pub load_balancer_ip: Option<TfOutput<String>>,

    #[serde(default)]
    pub external_login_password_mz_system: Option<TfOutput<String>>,

    /// kind only: the balancerd service verify port-forwards to reach SQL.
    #[serde(default)]
    pub balancerd_service_name: Option<TfOutput<String>>,
}

impl TerraformOutputs {
    pub fn cluster_name(&self, provider: CloudProvider) -> Result<&str> {
        let output = match provider {
            CloudProvider::Aws => &self.eks_cluster_name,
            CloudProvider::Gcp => &self.gke_cluster_name,
            CloudProvider::Azure => &self.aks_cluster_name,
            // The kind cluster is named after the test run, not a terraform output.
            CloudProvider::Kind => bail!("kind clusters have no cluster name output"),
        };
        output
            .as_ref()
            .map(|o| o.value.as_str())
            .context("Missing terraform output: cluster name")
    }

    pub fn load_balancer_endpoint(&self) -> Option<&str> {
        self.nlb_dns_name
            .as_ref()
            .map(|o| o.value.as_str())
            .or_else(|| self.load_balancer_ip.as_ref().map(|o| o.value.as_str()))
    }

    pub fn mz_password(&self) -> Result<&str> {
        self.external_login_password_mz_system
            .as_ref()
            .map(|o| o.value.as_str())
            .context("Missing output: external_login_password_mz_system")
    }
}
