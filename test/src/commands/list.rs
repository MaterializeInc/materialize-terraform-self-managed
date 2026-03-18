use anyhow::{Result, bail};

use crate::helpers::runs_dir;

pub async fn list(latest_only: bool) -> Result<()> {
    let runs = runs_dir()?;
    if !runs.exists() {
        bail!("No test runs directory found at {}", runs.display());
    }

    let mut entries: Vec<(std::time::SystemTime, String)> = Vec::new();
    let mut dir = tokio::fs::read_dir(&runs).await?;
    while let Some(entry) = dir.next_entry().await? {
        if entry.file_type().await?.is_dir() {
            let created = entry
                .metadata()
                .await?
                .created()
                .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
            let name = entry.file_name().to_string_lossy().to_string();
            entries.push((created, name));
        }
    }

    if entries.is_empty() {
        bail!("No test runs found in {}", runs.display());
    }

    entries.sort_by_key(|(created, _)| *created);

    if latest_only {
        println!("{}", entries.last().unwrap().1);
    } else {
        for (_, name) in &entries {
            println!("{name}");
        }
    }
    Ok(())
}
