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
// terraform.tfvars.json: written during init, read back by verify, destroy, sync and purge
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
        /// The example's optional Ory stack; `None` with `--skip-ory`.
        #[serde(flatten)]
        ory: Option<KindOryTfVars>,
    },
}

/// Turns on the kubernetes example's Ory stack, backed by the databases
/// test/kind/backends.yaml creates.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct KindOryTfVars {
    pub enable_ory: bool,
    pub ory_kratos_dsn: String,
    pub ory_hydra_dsn: String,
    pub ory_polis_dsn: String,
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
    pub balancerd_load_balancer_ip: Option<TfOutput<String>>,

    #[serde(default)]
    pub external_login_password_mz_system: Option<TfOutput<String>>,

    /// kind only: the balancerd service verify port-forwards to reach SQL.
    #[serde(default)]
    pub balancerd_service_name: Option<TfOutput<String>>,

    /// kind only: the Ory stack, null when the example leaves it off.
    #[serde(default)]
    pub ory: Option<TfOutput<Option<OryOutput>>>,
}

/// The kubernetes example's `ory` output.
#[derive(Debug, Deserialize)]
pub struct OryOutput {
    pub namespace: String,
    pub issuer: String,
    pub oauth2_client_secret_name: String,
    /// Keyed by component: hydra, kratos, ui and, when deployed, polis.
    pub services: HashMap<String, OryService>,
}

/// An Ory Service on port 443 and the hostname its certificate is issued for.
#[derive(Debug, Deserialize)]
pub struct OryService {
    pub name: String,
    pub host: String,
}

impl OryOutput {
    pub fn service(&self, component: &str) -> Result<&OryService> {
        self.services
            .get(component)
            .with_context(|| format!("Missing Ory service in terraform output: {component}"))
    }
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
            .or_else(|| {
                self.balancerd_load_balancer_ip
                    .as_ref()
                    .map(|o| o.value.as_str())
            })
    }

    pub fn ory(&self) -> Option<&OryOutput> {
        self.ory.as_ref().and_then(|o| o.value.as_ref())
    }

    pub fn mz_password(&self) -> Result<&str> {
        self.external_login_password_mz_system
            .as_ref()
            .map(|o| o.value.as_str())
            .context("Missing output: external_login_password_mz_system")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kind_tfvars(ory: Option<KindOryTfVars>) -> TfVars {
        TfVars::Kind {
            common: CommonTfVars {
                name_prefix: "t".into(),
                license_key: "k".into(),
                internal_load_balancer: None,
                grafana_allow_public_access: None,
                helm_chart: None,
                use_local_chart: None,
                orchestratord_version: None,
                environmentd_version: None,
            },
            kubeconfig_path: "./kubeconfig".into(),
            metadata_backend_url: "m".into(),
            persist_backend_url: "p".into(),
            ory,
        }
    }

    #[test]
    fn kind_ory_tfvars_round_trip() {
        let ory = KindOryTfVars {
            enable_ory: true,
            ory_kratos_dsn: "k".into(),
            ory_hydra_dsn: "h".into(),
            ory_polis_dsn: "p".into(),
        };
        let json = serde_json::to_value(kind_tfvars(Some(ory))).unwrap();
        assert_eq!(json["enable_ory"], true);
        assert_eq!(json["ory_hydra_dsn"], "h");
        let TfVars::Kind { ory, .. } = serde_json::from_value(json).unwrap() else {
            panic!("not kind");
        };
        assert!(ory.is_some());

        // --skip-ory, and runs initialized before Ory was added.
        let json = serde_json::to_value(kind_tfvars(None)).unwrap();
        assert!(json.get("enable_ory").is_none());
        let TfVars::Kind { ory, .. } = serde_json::from_value(json).unwrap() else {
            panic!("not kind");
        };
        assert!(ory.is_none());
    }
}
