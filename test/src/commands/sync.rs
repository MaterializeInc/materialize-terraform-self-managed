use std::path::Path;

use anyhow::Result;

use crate::commands::init::copy_example_files;
use crate::helpers::{ci_log_group, example_dir, project_root, read_tfvars};

/// Re-copies example .tf files into an existing test run directory,
/// overwriting the current versions. Useful for picking up local
/// changes to the terraform modules without re-initializing.
pub async fn phase_sync(dir: &Path) -> Result<()> {
    ci_log_group("Sync", || async {
        let tfvars = read_tfvars(dir)?;
        let provider = tfvars.cloud_provider();
        let src = example_dir(provider)?;
        let root = project_root()?;

        println!(
            "Syncing terraform files for test run: {}",
            dir.file_name().unwrap().to_string_lossy()
        );
        println!(
            "  Source: {}",
            src.strip_prefix(&root).unwrap_or(&src).display()
        );
        println!(
            "  Dest:   {}",
            dir.strip_prefix(&root).unwrap_or(dir).display()
        );

        println!("\nCopying terraform files...");
        copy_example_files(&src, dir, provider).await?;

        println!("\nSync completed successfully.");
        Ok(())
    })
    .await
}
