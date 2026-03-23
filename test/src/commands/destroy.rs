use std::path::Path;

use anyhow::{Context, Result};
use serde::Deserialize;
use tokio::process::Command;

use crate::helpers::{read_tfvars, run_cmd, run_cmd_output, write_lifecycle};
use crate::types::TfVars;

const MAX_DESTROY_ATTEMPTS: u32 = 3;

/// Runs `terraform destroy -auto-approve` in the test run directory.
/// If `rm` is true, removes the directory afterwards.
///
/// For AWS, if destroy fails (typically due to orphaned ENIs blocking
/// security group deletion), we clean up the ENIs and retry.
pub async fn phase_destroy(dir: &Path, rm: bool) -> Result<()> {
    write_lifecycle(dir, "destroy", "started").await?;
    println!("Destroying test run...");
    println!("  Directory: {}", dir.display());

    let tfvars = read_tfvars(dir)?;

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
                println!("\nDestroy attempt {attempt}/{MAX_DESTROY_ATTEMPTS} failed.");

                if let TfVars::Aws {
                    aws_region,
                    aws_profile,
                    ..
                } = &tfvars
                {
                    println!("Cleaning up orphaned ENIs before retrying...");
                    if let Err(cleanup_err) = cleanup_aws_enis(dir, aws_region, aws_profile).await {
                        println!("  Warning: ENI cleanup failed: {cleanup_err:#}");
                    }
                }

                println!("Retrying destroy...\n");
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
}

/// Cleans up orphaned ENIs that block security group deletion during
/// `terraform destroy`.
///
/// When Karpenter deletes a node mid-destroy, the aws-cni plugin on that
/// node may not have time to clean up ENIs it created. These ENIs remain
/// associated with the node security group, preventing terraform from
/// deleting it.
///
/// We look up the node security group ID from terraform state, find any
/// ENIs still using it, detach them if needed, and delete them.
async fn cleanup_aws_enis(dir: &Path, region: &str, profile: &str) -> Result<()> {
    let sg_id = get_node_security_group_id(dir)?;
    println!("  Node security group: {sg_id}");

    let eni_output = run_cmd_output(
        Command::new("aws")
            .args([
                "ec2",
                "describe-network-interfaces",
                "--filters",
                &format!("Name=group-id,Values={sg_id}"),
                "--query",
                "NetworkInterfaces[*].{Id:NetworkInterfaceId,AttachmentId:Attachment.AttachmentId,Status:Attachment.Status}",
                "--output",
                "json",
                "--region",
                region,
                "--profile",
                profile,
            ]),
    )
    .await
    .context("Failed to describe network interfaces")?;

    let enis: Vec<EniInfo> =
        serde_json::from_str(&eni_output).context("Failed to parse ENI describe output")?;

    if enis.is_empty() {
        println!("  No orphaned ENIs found.");
        return Ok(());
    }

    println!("  Found {} ENI(s) to clean up.", enis.len());

    for eni in &enis {
        // Detach if currently attached
        if let (Some(attachment_id), Some(status)) = (&eni.attachment_id, &eni.status)
            && status == "attached"
        {
            println!("  Detaching {} (attachment {})...", eni.id, attachment_id);
            let _ = run_cmd(Command::new("aws").args([
                "ec2",
                "detach-network-interface",
                "--attachment-id",
                attachment_id,
                "--force",
                "--region",
                region,
                "--profile",
                profile,
            ]))
            .await;

            // Wait for detachment to complete
            let _ = run_cmd(Command::new("aws").args([
                "ec2",
                "wait",
                "network-interface-available",
                "--network-interface-ids",
                &eni.id,
                "--region",
                region,
                "--profile",
                profile,
            ]))
            .await;
        }

        println!("  Deleting {}...", eni.id);
        let result = run_cmd(Command::new("aws").args([
            "ec2",
            "delete-network-interface",
            "--network-interface-id",
            &eni.id,
            "--region",
            region,
            "--profile",
            profile,
        ]))
        .await;

        if let Err(e) = result {
            // Non-fatal: the ENI might be legitimately in use
            println!("  Warning: could not delete {}: {e:#}", eni.id);
        }
    }

    println!("  ENI cleanup complete.");
    Ok(())
}

/// Gets the node security group ID from terraform state.
///
/// Parses the HCL-style output of `terraform state show` to extract the `id`
/// field, since `terraform state show` does not support `-json`.
fn get_node_security_group_id(dir: &Path) -> Result<String> {
    let output = std::process::Command::new("terraform")
        .args([
            "state",
            "show",
            "module.eks.module.eks.aws_security_group.node[0]",
        ])
        .current_dir(dir)
        .output()
        .context("Failed to read terraform state")?;

    if !output.status.success() {
        anyhow::bail!(
            "terraform state show failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let stdout = String::from_utf8(output.stdout)?;
    for line in stdout.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("id") {
            let rest = rest.trim();
            if let Some(rest) = rest.strip_prefix('=') {
                let id = rest.trim().trim_matches('"');
                if id.starts_with("sg-") {
                    return Ok(id.to_string());
                }
            }
        }
    }

    anyhow::bail!("Could not find id in terraform state show output")
}

#[derive(Debug, Deserialize)]
struct EniInfo {
    #[serde(rename = "Id")]
    id: String,
    #[serde(rename = "AttachmentId")]
    attachment_id: Option<String>,
    #[serde(rename = "Status")]
    status: Option<String>,
}
