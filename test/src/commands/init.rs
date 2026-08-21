use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use tokio::process::Command;

use crate::cli::InitProvider;
use crate::helpers::{
    ci_log_group, example_dir, generate_test_run_id, project_root, run_cmd, runs_dir,
    upload_tfvars_to_backend, write_lifecycle,
};
use crate::types::{CloudProvider, CommonTfVars, TfVars};

/// Initializes a new test run: copies example .tf files, writes tfvars,
/// runs `terraform init`. Returns the path to the new test run directory.
pub async fn phase_init(provider_args: &InitProvider) -> Result<PathBuf> {
    ci_log_group("Init", || async {
        let provider = provider_args.cloud_provider();
        let test_run_id = generate_test_run_id();
        let src = example_dir(provider)?;
        let root = project_root()?;
        let dest = runs_dir()?.join(&test_run_id);

        println!("Initializing test run: {test_run_id}");
        println!(
            "  Source: {}",
            src.strip_prefix(&root).unwrap_or(&src).display()
        );
        println!(
            "  Dest:   {}",
            dest.strip_prefix(&root).unwrap_or(&dest).display()
        );

        tokio::fs::create_dir_all(&dest).await?;
        write_lifecycle(&dest, "init", "started").await?;

        println!("\nCopying terraform files...");
        copy_example_files(&src, &dest, provider).await?;

        // When any dev overrides are provided (--local-chart-path,
        // --orchestratord-version, --environmentd-version), create
        // dev_variables.tf and inject the corresponding variables into
        // the relevant module blocks in main.tf.
        let common = provider_args.common();
        let overrides = DevOverrides {
            local_chart: common.local_chart_path.is_some(),
            orchestratord_version: common.orchestratord_version.is_some(),
            environmentd_version: common.environmentd_version.is_some(),
        };
        // The kubernetes example (used by kind) declares these variables
        // natively -- its operator is a helm_release, not a module -- so
        // injection is neither needed nor possible there.
        if overrides.any() && provider != CloudProvider::Kind {
            println!("\nApplying dev overrides...");
            write_dev_variables_tf(&dest).await?;
            inject_dev_overrides(&dest, &overrides).await?;
        }

        println!("\nBuilding terraform.tfvars.json...");
        let tfvars = build_tfvars(provider_args, &test_run_id)?;
        let tfvars_path = dest.join("terraform.tfvars.json");
        let tfvars_json = serde_json::to_string_pretty(&tfvars)?;
        tokio::fs::write(&tfvars_path, &tfvars_json).await?;
        println!("  Wrote {}", tfvars_path.display());
        let mut redacted = tfvars.clone();
        redacted.common_mut().license_key = "REDACTED".to_string();
        println!("{}", serde_json::to_string_pretty(&redacted)?);

        if let Some(backend_tf) = provider_args.backend_config(&test_run_id) {
            println!("\nConfiguring remote backend...");
            let backend_path = dest.join("backend.tf");
            tokio::fs::write(&backend_path, &backend_tf).await?;
            println!("  Wrote {}", backend_path.display());
            println!("{backend_tf}");
        }

        upload_tfvars_to_backend(&dest).await?;

        // The cloud providers get their cluster from `terraform apply`; for
        // kind the cluster is local infrastructure that terraform runs
        // against, so it is created during init. After the tfvars are
        // written, so a failed creation can still be cleaned up by `destroy`.
        if provider == CloudProvider::Kind {
            println!("\nCreating kind cluster {test_run_id}...");
            create_kind_cluster(&test_run_id, &dest).await?;
        }

        println!("\nRunning terraform init...");
        let init_result = run_cmd(Command::new("terraform").arg("init").current_dir(&dest))
            .await
            .context("terraform init failed");
        if let Err(e) = init_result {
            // A failed init returns before `run --destroy-on-failure` gets a
            // test run to destroy, so the just-created kind cluster would
            // leak. Best-effort delete; the clouds have nothing to clean up.
            if provider == CloudProvider::Kind {
                run_cmd(Command::new("kind").args(["delete", "cluster", "--name", &test_run_id]))
                    .await
                    .ok();
            }
            return Err(e);
        }

        write_lifecycle(&dest, "init", "completed").await?;
        println!("\nTest run initialized successfully: {test_run_id}");
        Ok(dest)
    })
    .await
}

/// Copies .tf files from the example directory to the test run directory,
/// rewriting relative module source paths to account for the new location.
pub(crate) async fn copy_example_files(
    src: &Path,
    dest: &Path,
    provider: CloudProvider,
) -> Result<()> {
    tokio::fs::create_dir_all(dest)
        .await
        .context("Failed to create test run directory")?;

    let mut entries = tokio::fs::read_dir(src).await?;
    while let Some(entry) = entries.next_entry().await? {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();

        // Skip files we don't want to copy
        if !name_str.ends_with(".tf")
            || name_str == "dev_variables.tf"
            || name_str.starts_with("terraform.tfstate")
        {
            continue;
        }

        let file_type = entry.file_type().await?;
        if file_type.is_file() {
            let content = tokio::fs::read_to_string(entry.path()).await?;
            let rewritten = rewrite_module_sources(&content, provider)?;
            let dest_file = dest.join(&name);
            tokio::fs::write(&dest_file, rewritten).await?;
            println!("  Copied {}", name_str);
        }
    }
    Ok(())
}

/// Rewrites module source paths from the example directory layout to the
/// test/runs/{id}/ layout.
fn rewrite_module_sources(content: &str, provider: CloudProvider) -> Result<String> {
    use hcl_edit::expr::Expression;

    let provider_dir = provider.dir_name();
    let old_prefix = "../../modules/";
    let new_prefix = format!("../../../{provider_dir}/modules/");

    let mut body: hcl_edit::structure::Body =
        content.parse().context("Failed to parse terraform file")?;

    for block in body.get_blocks_mut("module") {
        if let Some(mut attr) = block.body.get_attribute_mut("source") {
            let new_val = attr
                .get()
                .value
                .as_str()
                .filter(|s| s.starts_with(old_prefix))
                .map(|s| s.replacen(old_prefix, &new_prefix, 1));
            if let Some(new_val) = new_val {
                *attr.value_mut() = Expression::from(new_val);
            }
        }
    }

    Ok(body.to_string())
}

/// Converts a string to a valid GCP label value: lowercase, replacing
/// invalid characters (spaces, uppercase) with hyphens, and trimming
/// leading/trailing non-alphanumeric characters.
fn to_gcp_label(s: &str) -> String {
    let normalized: String = s
        .to_lowercase()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' {
                c
            } else {
                '-'
            }
        })
        .collect();
    normalized
        .trim_matches(|c: char| !c.is_ascii_alphanumeric())
        .to_string()
}

fn build_tfvars(provider_args: &InitProvider, test_run_id: &str) -> Result<TfVars> {
    let common = provider_args.common();

    let (helm_chart, use_local_chart) = if let Some(chart_path) = &common.local_chart_path {
        let canonical =
            std::fs::canonicalize(chart_path).context("Failed to resolve --local-chart-path")?;
        (Some(canonical.to_string_lossy().into_owned()), Some(true))
    } else {
        (None, None)
    };

    let common_tf = CommonTfVars {
        name_prefix: test_run_id.to_string(),
        license_key: common.resolve_license_key()?,
        internal_load_balancer: internal_load_balancer(provider_args),
        grafana_allow_public_access: grafana_allow_public_access(provider_args),
        helm_chart,
        use_local_chart,
        orchestratord_version: common.orchestratord_version.clone(),
        environmentd_version: common.environmentd_version.clone(),
    };

    Ok(match provider_args {
        InitProvider::Kind { .. } => TfVars::Kind {
            common: common_tf,
            kubeconfig_path: "./kubeconfig".into(),
            // The in-cluster backends from test/kind/backends.yaml.
            metadata_backend_url: "postgres://materialize:materialize@postgres.backends.svc.cluster.local:5432/materialize?sslmode=disable".into(),
            persist_backend_url: "s3://rustfsadmin:rustfsadmin@materialize/persist?endpoint=http%3A%2F%2Frustfs.backends.svc.cluster.local%3A9000&region=us-east-1".into(),
        },
        InitProvider::Aws {
            aws_region,
            aws_profile,
            ..
        } => TfVars::Aws {
            common: common_tf,
            aws_region: aws_region.clone(),
            aws_profile: aws_profile.clone(),
            tags: HashMap::from([
                ("Purpose".into(), common.purpose.clone()),
                ("TestRun".into(), test_run_id.into()),
                // The scratch account's RequireTagsScratch SCP
                // (MaterializeInc/i2) denies resource creation unless these
                // four tags are present. Lowercase `owner` replaces the
                // previous `Owner` tag outright: IAM tag keys are
                // case-insensitive, so carrying both fails CreateRole with
                // "Duplicate tag keys found".
                ("owner".into(), common.owner.clone()),
                ("reason".into(), common.reason.clone()),
                ("team".into(), common.team.clone()),
                (
                    "deleteAfter".into(),
                    (chrono::Utc::now() + chrono::Duration::hours(common.delete_after_hours))
                        .format("%Y-%m-%dT%H:%M:%SZ")
                        .to_string(),
                ),
            ]),
        },
        InitProvider::Azure {
            subscription_id,
            resource_group_name,
            location,
            ..
        } => TfVars::Azure {
            common: common_tf,
            subscription_id: subscription_id.clone(),
            resource_group_name: resource_group_name
                .clone()
                .unwrap_or_else(|| test_run_id.to_string()),
            location: location.clone(),
            tags: HashMap::from([
                ("Owner".into(), common.owner.clone()),
                ("Purpose".into(), common.purpose.clone()),
                ("TestRun".into(), test_run_id.into()),
            ]),
        },
        InitProvider::Gcp {
            project_id, region, ..
        } => TfVars::Gcp {
            common: common_tf,
            project_id: project_id.clone(),
            region: region.clone(),
            // GCP labels must be lowercase keys/values matching [a-z0-9_-.].
            labels: HashMap::from([
                ("owner".into(), to_gcp_label(&common.owner)),
                ("purpose".into(), to_gcp_label(&common.purpose)),
                ("test-run".into(), test_run_id.into()),
            ]),
        },
    })
}

/// Writes a `dev_variables.tf` file into the test run directory, defining
/// optional override variables for local development.
pub(crate) async fn write_dev_variables_tf(dest: &Path) -> Result<()> {
    let content = r#"variable "helm_chart" {
  description = "Chart name from repository or local path to chart. For local charts, set the path to the chart directory."
  type        = string
  default     = null
}

variable "use_local_chart" {
  description = "Whether to use a local chart instead of one from a repository"
  type        = bool
  default     = null
}

variable "orchestratord_version" {
  description = "Version of the Materialize orchestrator to install"
  type        = string
  default     = null
}

variable "environmentd_version" {
  description = "Version of environmentd to use"
  type        = string
  default     = null
}
"#;
    let path = dest.join("dev_variables.tf");
    tokio::fs::write(&path, content).await?;
    println!("  Wrote dev_variables.tf");
    Ok(())
}

/// Flags that control which dev-override variables to inject into `main.tf`.
pub(crate) struct DevOverrides {
    pub local_chart: bool,
    pub orchestratord_version: bool,
    pub environmentd_version: bool,
}

impl DevOverrides {
    /// Returns `true` if any override is active.
    pub fn any(&self) -> bool {
        self.local_chart || self.orchestratord_version || self.environmentd_version
    }
}

/// Injects dev-override variable references into the appropriate module
/// blocks in `main.tf`. Each injection is skipped if the variable reference
/// is already present in the file.
pub(crate) async fn inject_dev_overrides(dest: &Path, overrides: &DevOverrides) -> Result<()> {
    let main_tf_path = dest.join("main.tf");
    let content = tokio::fs::read_to_string(&main_tf_path)
        .await
        .context("Failed to read main.tf")?;

    let mut body: hcl_edit::structure::Body = content.parse().context("Failed to parse main.tf")?;

    let mut changed = false;

    // Operator module: helm_chart, use_local_chart, orchestratord_version
    let operator_vars: Vec<&str> = [
        (overrides.local_chart, "helm_chart"),
        (overrides.local_chart, "use_local_chart"),
        (overrides.orchestratord_version, "orchestratord_version"),
    ]
    .iter()
    .filter(|(needed, _)| *needed)
    .map(|(_, key)| *key)
    .collect();

    if !operator_vars.is_empty() {
        let module = find_module_mut(&mut body, "operator")?;
        for &key in &operator_vars {
            changed |= set_module_var(module, "operator", key);
        }
    }

    // Materialize instance module: environmentd_version
    if overrides.environmentd_version {
        let module = find_module_mut(&mut body, "materialize_instance")?;
        changed |= set_module_var(module, "materialize_instance", "environmentd_version");
    }

    if changed {
        tokio::fs::write(&main_tf_path, body.to_string()).await?;
    }

    Ok(())
}

/// Points `<key>` at `var.<key>` in the given module block, replacing whatever
/// value is already there.
///
/// The examples wire some of these attributes to a different variable of their
/// own -- every simple example has `environmentd_version = var.materialize_version`
/// -- so an injection that skipped when the attribute was already present left
/// the dev override silently unused: the variable was declared in
/// `dev_variables.tf` and set in `terraform.tfvars.json`, but nothing read it,
/// and terraform does not warn about a declared-but-unreferenced variable. The
/// run then came up on the module's default version.
///
/// Returns whether the module block was modified.
fn set_module_var(module: &mut hcl_edit::structure::Block, module_name: &str, key: &str) -> bool {
    let want = format!("var.{key}");

    let Some(mut attr) = module.body.get_attribute_mut(key) else {
        module.body.push(module_var_attr(key));
        println!("  Injected {key} into {module_name} module in main.tf");
        return true;
    };

    let current = attr.value_mut().to_string();
    let current = current.trim();
    if current == want {
        return false;
    }
    println!("  Repointed {key} from {current} to {want} in {module_name} module in main.tf");
    *attr.value_mut() = var_ref(key);
    true
}

/// Finds a `module "<name>"` block in the body, returning a mutable reference.
fn find_module_mut<'a>(
    body: &'a mut hcl_edit::structure::Body,
    name: &str,
) -> Result<&'a mut hcl_edit::structure::Block> {
    body.get_blocks_mut("module")
        .find(|b| b.has_labels(&[name]))
        .with_context(|| format!("could not find module \"{name}\" in tf file"))
}

/// Builds an `Attribute` like `key = var.key` with 2-space indentation to
/// match the surrounding module block.
fn module_var_attr(name: &str) -> hcl_edit::structure::Attribute {
    use hcl_edit::Decorate;

    let mut attr = hcl_edit::structure::Attribute::new(hcl_edit::Ident::new(name), var_ref(name));
    attr.decor_mut().set_prefix("  ");
    attr
}

/// Builds a `var.<name>` traversal expression.
fn var_ref(name: &str) -> hcl_edit::expr::Expression {
    use hcl_edit::Decorated;
    use hcl_edit::expr::{Traversal, TraversalOperator};

    Traversal::new(
        hcl_edit::Ident::new("var"),
        vec![Decorated::new(TraversalOperator::GetAttr(Decorated::new(
            hcl_edit::Ident::new(name),
        )))],
    )
    .into()
}

/// The two load-balancer acknowledgements only exist as variables in the
/// cloud roots; kind has no load balancers, so they are omitted from its
/// tfvars entirely (terraform warns about unused tfvars values).
fn internal_load_balancer(provider_args: &InitProvider) -> Option<bool> {
    match provider_args {
        InitProvider::Kind { .. } => None,
        _ => Some(false),
    }
}

fn grafana_allow_public_access(provider_args: &InitProvider) -> Option<bool> {
    match provider_args {
        InitProvider::Kind { .. } => None,
        _ => Some(true),
    }
}

/// Creates the kind cluster for a test run, writes its kubeconfig into the
/// test run directory (where the copied terraform root expects it), and
/// deploys the in-cluster PostgreSQL/RustFS backends the example needs.
async fn create_kind_cluster(test_run_id: &str, dest: &Path) -> Result<()> {
    let kind_dir = project_root()?.join("test/kind");
    let kubeconfig = dest.join("kubeconfig");
    run_cmd(
        Command::new("kind")
            .args(["create", "cluster", "--name", test_run_id, "--wait", "120s"])
            .arg("--config")
            .arg(kind_dir.join("cluster.yaml"))
            .arg("--kubeconfig")
            .arg(&kubeconfig),
    )
    .await
    .context("kind create cluster failed")?;

    run_cmd(
        crate::helpers::kubectl(&kubeconfig)
            .arg("apply")
            .arg("-f")
            .arg(kind_dir.join("backends.yaml")),
    )
    .await
    .context("failed to deploy the kind test backends")
}
