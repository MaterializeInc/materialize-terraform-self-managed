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
        if overrides.any() {
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

        println!("\nRunning terraform init...");
        run_cmd(Command::new("terraform").arg("init").current_dir(&dest))
            .await
            .context("terraform init failed")?;

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
        internal_load_balancer: false,
        helm_chart,
        use_local_chart,
        orchestratord_version: common.orchestratord_version.clone(),
        environmentd_version: common.environmentd_version.clone(),
    };

    Ok(match provider_args {
        InitProvider::Aws {
            aws_region,
            aws_profile,
            ..
        } => TfVars::Aws {
            common: common_tf,
            aws_region: aws_region.clone(),
            aws_profile: aws_profile.clone(),
            tags: HashMap::from([
                ("Owner".into(), common.owner.clone()),
                ("Purpose".into(), common.purpose.clone()),
                ("TestRun".into(), test_run_id.into()),
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
            if !module.body.has_attribute(key) {
                module.body.push(module_var_attr(key));
                changed = true;
                println!("  Injected {key} into operator module in main.tf");
            }
        }
    }

    // Materialize instance module: environmentd_version
    if overrides.environmentd_version {
        let module = find_module_mut(&mut body, "materialize_instance")?;
        if !module.body.has_attribute("environmentd_version") {
            module.body.push(module_var_attr("environmentd_version"));
            changed = true;
            println!("  Injected environmentd_version into materialize_instance module in main.tf");
        }
    }

    if changed {
        tokio::fs::write(&main_tf_path, body.to_string()).await?;
    }

    Ok(())
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

    let mut attr = hcl_edit::structure::Attribute::new(
        hcl_edit::Ident::new(name),
        var_ref(name),
    );
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
