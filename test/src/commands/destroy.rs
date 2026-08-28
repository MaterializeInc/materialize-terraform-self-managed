use std::path::Path;

use anyhow::{Context, Result};
use tokio::process::Command;

use crate::commands::purge::delete_detached_enis;
use crate::helpers::{ci_log_group, delete_backend_state, read_tfvars, run_cmd, write_lifecycle};
use crate::types::CloudProvider;

const MAX_DESTROY_ATTEMPTS: u32 = 3;

/// Tears down a test run: `terraform destroy -auto-approve` for the cloud
/// providers, `kind delete cluster` for kind. If `rm` is true, removes the
/// directory afterwards.
pub async fn phase_destroy(dir: &Path, rm: bool) -> Result<()> {
    ci_log_group("Destroy", || async {
        write_lifecycle(dir, "destroy", "started").await?;
        println!("Destroying test run...");
        println!("  Directory: {}", dir.display());

        if read_tfvars(dir)?.cloud_provider() == CloudProvider::Kind {
            // Everything a kind run creates lives in the kind cluster, so
            // deleting the cluster replaces `terraform destroy`.
            let cluster_name = dir.file_name().unwrap().to_string_lossy();
            run_cmd(
                Command::new("kind")
                    .args(["delete", "cluster", "--name", &cluster_name])
                    .arg("--kubeconfig")
                    .arg(dir.join("kubeconfig")),
            )
            .await
            .context("kind delete cluster failed")?;
        } else {
            destroy_terraform(dir).await?;
        }

        if rm {
            delete_backend_state(dir).await?;
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

/// Runs `terraform destroy -auto-approve` with retries on transient failures,
/// clearing the run's detached ENIs before each retry. The EKS module's
/// destroy-time ENI cleanup runs once, as soon as the managed node group is
/// gone, and only sees the ENIs detached by then. Any that detach later are
/// left behind for good, and hold the node security group against every
/// subsequent attempt with `DependencyViolation`.
async fn destroy_terraform(dir: &Path) -> Result<()> {
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
                if let Err(e) = delete_detached_enis(dir).await {
                    println!("ENI cleanup before retry failed: {e:#}");
                }
            }
            Err(e) => return Err(e).context("terraform destroy failed after all attempts"),
        }
    }
    Ok(())
}
