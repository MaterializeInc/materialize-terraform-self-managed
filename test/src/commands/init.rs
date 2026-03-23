use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use tokio::process::Command;

use crate::cli::InitProvider;
use crate::helpers::{
    example_dir, generate_test_run_id, project_root, run_cmd, runs_dir, write_lifecycle,
};
use crate::types::{CloudProvider, CommonTfVars, TfVars};

/// Initializes a new test run: copies example .tf files, writes tfvars,
/// runs `terraform init`. Returns the path to the new test run directory.
pub async fn phase_init(provider_args: &InitProvider) -> Result<PathBuf> {
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

    println!("\nRunning terraform init...");
    run_cmd(Command::new("terraform").arg("init").current_dir(&dest))
        .await
        .context("terraform init failed")?;

    write_lifecycle(&dest, "init", "completed").await?;
    println!("\nTest run initialized successfully: {test_run_id}");
    Ok(dest)
}

/// Copies .tf files from the example directory to the test run directory,
/// rewriting relative module source paths to account for the new location.
async fn copy_example_files(src: &Path, dest: &Path, provider: CloudProvider) -> Result<()> {
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
            let rewritten = rewrite_module_sources(&content, provider);
            let dest_file = dest.join(&name);
            tokio::fs::write(&dest_file, rewritten).await?;
            println!("  Copied {}", name_str);
        }
    }
    Ok(())
}

/// Rewrites module source paths from the example directory layout to the
/// test/runs/{id}/ layout.
fn rewrite_module_sources(content: &str, provider: CloudProvider) -> String {
    let provider_dir = provider.dir_name();
    // Provider-specific modules: ../../modules/ → ../../../{provider}/modules/
    // (the original goes up 2 levels to {provider}/, we need up 3 to root then into {provider}/)
    content.replace(
        "\"../../modules/",
        &format!("\"../../../{provider_dir}/modules/"),
    )
    // Kubernetes modules: ../../../kubernetes/ stays the same (already 3 levels up to root)
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
    let common_tf = CommonTfVars {
        name_prefix: test_run_id.to_string(),
        license_key: common.resolve_license_key()?,
        internal_load_balancer: false,
        helm_chart: common.helm_chart.clone(),
        use_local_chart: if common.use_local_chart {
            Some(true)
        } else {
            None
        },
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
            resource_group_name: resource_group_name.clone(),
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
