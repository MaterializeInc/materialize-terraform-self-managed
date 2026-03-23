use std::path::Path;

use std::time::Duration;

use anyhow::{Context, Result};
use tokio::process::Command;

use crate::helpers::{ci_log_group, run_cmd, write_lifecycle};

const MAX_APPLY_ATTEMPTS: u32 = 3;
const RETRY_DELAY: Duration = Duration::from_secs(30);

/// Runs `terraform apply -auto-approve` in the test run directory.
///
/// Retries on failure to handle transient provider errors (e.g. GCP
/// Cloud SQL instance creation timeouts).
pub async fn phase_apply(dir: &Path) -> Result<()> {
    ci_log_group("Apply", || async {
        write_lifecycle(dir, "apply", "started").await?;
        println!("Applying test run...");
        println!("  Directory: {}", dir.display());

        for attempt in 1..=MAX_APPLY_ATTEMPTS {
            let result = run_cmd(
                Command::new("terraform")
                    .args(["apply", "-auto-approve"])
                    .current_dir(dir),
            )
            .await;

            match result {
                Ok(()) => break,
                Err(_) if attempt < MAX_APPLY_ATTEMPTS => {
                    println!(
                        "\nApply attempt {attempt}/{MAX_APPLY_ATTEMPTS} failed. Retrying in {}s...\n",
                        RETRY_DELAY.as_secs()
                    );
                    tokio::time::sleep(RETRY_DELAY).await;
                }
                Err(e) => return Err(e).context("terraform apply failed after all attempts"),
            }
        }

        write_lifecycle(dir, "apply", "completed").await?;
        println!("\nApply completed successfully.");
        Ok(())
    }).await
}
