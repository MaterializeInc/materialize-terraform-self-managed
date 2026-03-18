use std::path::Path;

use anyhow::{Context, Result};
use tokio::process::Command;

use crate::helpers::{run_cmd, write_lifecycle};

/// Runs `terraform apply -auto-approve` in the test run directory.
pub async fn phase_apply(dir: &Path) -> Result<()> {
    write_lifecycle(dir, "apply", "started").await?;
    println!("Applying test run...");
    println!("  Directory: {}", dir.display());

    run_cmd(
        Command::new("terraform")
            .args(["apply", "-auto-approve"])
            .current_dir(dir),
    )
    .await
    .context("terraform apply failed")?;

    write_lifecycle(dir, "apply", "completed").await?;
    println!("\nApply completed successfully.");
    Ok(())
}
