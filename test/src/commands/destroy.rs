use std::path::Path;

use anyhow::{Context, Result};
use tokio::process::Command;

use crate::helpers::{ci_log_group, run_cmd, write_lifecycle};

const MAX_DESTROY_ATTEMPTS: u32 = 3;

/// Runs `terraform destroy -auto-approve` in the test run directory.
/// If `rm` is true, removes the directory afterwards.
///
/// Retries on transient failures. Orphaned ENI cleanup for AWS is
/// handled by a destroy-time provisioner in the EKS Terraform module.
pub async fn phase_destroy(dir: &Path, rm: bool) -> Result<()> {
    ci_log_group("Destroy", || async {
        write_lifecycle(dir, "destroy", "started").await?;
        println!("Destroying test run...");
        println!("  Directory: {}", dir.display());

        for attempt in 1..=MAX_DESTROY_ATTEMPTS {
            let result = run_cmd(
                Command::new("terraform")
                    .args(["destroy", "-auto-approve"])
                    .current_dir(dir),
            )
            .await;

            match result {
                Ok(()) => break,
                Err(_) if attempt < MAX_DESTROY_ATTEMPTS => {
                    println!(
                        "\nDestroy attempt {attempt}/{MAX_DESTROY_ATTEMPTS} failed. Retrying...\n"
                    );
                }
                Err(e) => return Err(e).context("terraform destroy failed after all attempts"),
            }
        }

        if rm {
            tokio::fs::remove_dir_all(dir).await?;
            println!(
                "\nDestroy completed successfully. Removed {}",
                dir.display()
            );
        } else {
            write_lifecycle(dir, "destroy", "completed").await?;
            println!("\nDestroy completed successfully.");
            println!("Note: Test run directory preserved at {}", dir.display());
        }
        Ok(())
    })
    .await
}
