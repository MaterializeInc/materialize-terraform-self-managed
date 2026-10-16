//! Measures the object store backing persist, and the SQL it has to serve.
//!
//! Not part of `run`: a benchmark holds a cluster for as long as the matrix
//! takes and produces numbers rather than a pass or fail, so it is a separate
//! command against an already-applied test run.
//!
//! Two layers, because they answer different questions. The blob layer drives
//! the store through persist's own S3 client and says what the store can do.
//! The SQL layer runs queries and says whether any of that reaches a user,
//! which it often does not: persist's blob cache absorbs a great deal.

use std::path::Path;

use anyhow::{Context, Result};
use tokio::process::Command;

use crate::helpers::{ci_log_group, read_tfvars, run_cmd, run_cmd_output};

/// How the benchmark client reaches the store and where it runs.
struct StoreTarget {
    /// Connection URL in the form `persistcli bench blob` accepts directly.
    blob_uri: String,
    namespace: String,
    /// Set when the store authenticates by identity rather than by keys in
    /// the URL, which is how a cloud provider's own object store is reached.
    service_account: Option<String>,
    /// Empty unless the store sits on a dedicated node pool.
    node_selector: serde_json::Value,
    tolerations: serde_json::Value,
}

pub async fn phase_benchmark(dir: &Path, args: &crate::cli::BenchmarkArgs) -> Result<()> {
    ci_log_group("Benchmark", || async {
        let tfvars = read_tfvars(dir)?;
        let provider = tfvars.cloud_provider();

        if !args.skip_blob {
            let target = store_target(dir, args).await.context(
                "This run has no in-cluster object store. Re-init with \
                     --persist-backend to benchmark one, name a store with \
                     --blob-uri, or pass --skip-blob",
            )?;
            run_blob_benchmark(dir, args, &target).await?;
        }

        if !args.skip_sql {
            println!("\nSQL-level benchmark is not implemented yet; skipping.");
            let _ = provider;
        }

        Ok(())
    })
    .await
}

/// Reads the store's connection details from the outputs the injector wrote,
/// letting `--blob-uri` and `--namespace` name a store those outputs do not
/// describe.
///
/// Placement always comes from the outputs, including when the target is
/// elsewhere: running every store's client on the same nodes is what makes
/// one set of numbers comparable to the next.
///
/// Only the URL and namespace are required. The placement hints are optional
/// because they are absent whenever the store has no node pool of its own: on
/// kind there is nothing to pin to, and a targeted apply does not evaluate
/// outputs that are pure variable pass-throughs. Treating them as fatal would
/// refuse to benchmark a store that is running perfectly well.
async fn store_target(dir: &Path, args: &crate::cli::BenchmarkArgs) -> Result<StoreTarget> {
    let blob_uri = match &args.blob_uri {
        Some(uri) => uri.clone(),
        None => tf_output_raw(dir, "object_store_persist_backend_url").await?,
    };
    let namespace = match &args.namespace {
        Some(ns) => ns.clone(),
        None => tf_output_raw(dir, "object_store_namespace").await?,
    };

    let node_selector = tf_output_json(dir, "object_store_node_selector")
        .await
        .unwrap_or_else(|_| serde_json::json!({}));
    let tolerations = tf_output_json(dir, "object_store_tolerations")
        .await
        .unwrap_or_else(|_| serde_json::json!([]));

    if node_selector.as_object().is_none_or(|m| m.is_empty()) {
        println!(
            "  Note: the store has no node pool of its own, so the benchmark \
             runs wherever the scheduler puts it. Numbers may include the \
             network between the client and the store."
        );
    }

    Ok(StoreTarget {
        blob_uri,
        namespace,
        service_account: args.service_account.clone(),
        node_selector,
        tolerations,
    })
}

async fn tf_output_raw(dir: &Path, name: &str) -> Result<String> {
    let out = run_cmd_output(
        Command::new("terraform")
            .args(["output", "-raw", name])
            .current_dir(dir),
    )
    .await
    .with_context(|| format!("terraform output -raw {name}"))?;
    Ok(out.trim().to_string())
}

async fn tf_output_json(dir: &Path, name: &str) -> Result<serde_json::Value> {
    let out = run_cmd_output(
        Command::new("terraform")
            .args(["output", "-json", name])
            .current_dir(dir),
    )
    .await
    .with_context(|| format!("terraform output -json {name}"))?;
    serde_json::from_str(out.trim()).with_context(|| format!("parsing {name} as json"))
}

/// Runs `persistcli bench blob` from inside the cluster.
///
/// In-cluster rather than through a port-forward on purpose: reaching a store
/// from outside costs enough to dominate the measurement, so a client outside
/// the cluster times the tunnel rather than the store. Pinned to the store's
/// own nodes for the same reason, when it has any.
async fn run_blob_benchmark(
    dir: &Path,
    args: &crate::cli::BenchmarkArgs,
    target: &StoreTarget,
) -> Result<()> {
    let kubeconfig = dir.join("kubeconfig");

    let sizes: Vec<u64> = args
        .sizes
        .split(',')
        .map(|s| s.trim().parse::<u64>().context("parsing --sizes"))
        .collect::<Result<_>>()?;

    println!("Running the blob benchmark...");
    println!("  sizes:       {}", args.sizes);
    println!("  concurrency: {}", args.concurrency);
    println!("  namespace:   {}", target.namespace);
    if let Some(account) = &target.service_account {
        println!("  as:          {account}");
    }

    // One Job per size rather than one Job looping over all of them: the image
    // carrying persistcli has no shell, so the container command has to be the
    // binary itself with its arguments, and a matrix needs one invocation per
    // cell.
    let mut rows = Vec::new();
    for size in sizes {
        let count = (args.bytes_per_cell / size).clamp(1, args.max_objects);
        let job_name = format!("blob-bench-{}", crate::helpers::generate_test_run_id());

        println!(
            "\n  {size} B x {count} at concurrency {}...",
            args.concurrency
        );

        let manifest = blob_job_manifest(&job_name, args, target, size, count)?;
        let manifest_path = dir.join(format!("{job_name}.yaml"));
        tokio::fs::write(&manifest_path, &manifest).await?;

        run_cmd(
            Command::new("kubectl")
                .args(["--kubeconfig"])
                .arg(&kubeconfig)
                .args(["apply", "-f"])
                .arg(&manifest_path),
        )
        .await
        .context("failed to create the benchmark job")?;

        let waited = run_cmd(
            Command::new("kubectl")
                .args(["--kubeconfig"])
                .arg(&kubeconfig)
                .args([
                    "wait",
                    "--for=condition=complete",
                    &format!("job/{job_name}"),
                    "-n",
                    &target.namespace,
                    &format!("--timeout={}s", args.timeout_secs),
                ]),
        )
        .await;

        let logs = run_cmd_output(
            Command::new("kubectl")
                .args(["--kubeconfig"])
                .arg(&kubeconfig)
                .args([
                    "logs",
                    &format!("job/{job_name}"),
                    "-n",
                    &target.namespace,
                    "--tail=-1",
                ]),
        )
        .await
        .unwrap_or_default();

        // Report the cell's own output before failing, since that is where the
        // reason lives when persistcli rejects a combination of arguments.
        if let Err(e) = waited {
            if !logs.trim().is_empty() {
                println!("{logs}");
            }
            if logs.contains("unrecognized subcommand 'blob'") {
                anyhow::bail!(
                    "The image does not provide `persistcli bench blob`, which this \
                     benchmark drives the store with. Published `materialize/jobs` \
                     images carry only `bench s3-fetch`, which reads an existing \
                     shard rather than running a write/read/delete matrix. Use an \
                     image built from a branch that has the `blob` subcommand, or \
                     pass --skip-blob."
                );
            }
            return Err(e).with_context(|| format!("cell {size} B did not complete"));
        }

        // persistcli already emits the size as its second column, so the rows
        // go in as it printed them. Its tracing output shares the same stream,
        // so an SDK warning logged mid-run would land in the CSV as if it were
        // a measurement. Only lines opening with an operation name are kept;
        // the rest are echoed but not recorded.
        for line in logs.lines().filter(|l| !l.trim().is_empty()) {
            println!("    {line}");
            if ["set,", "get,", "delete,", "list,"]
                .iter()
                .any(|op| line.starts_with(op))
            {
                rows.push(line.to_string());
            }
        }

        tokio::fs::remove_file(&manifest_path).await.ok();
    }

    // Matches what `persistcli bench blob` prints with --no-header.
    let mut csv = String::from(
        "op,size_bytes,concurrency,ops,bytes,elapsed_secs,ops_per_sec,mib_per_sec,p50_ms,p90_ms,p99_ms,max_ms,retries\n",
    );
    csv.push_str(&rows.join("\n"));
    csv.push('\n');

    let csv_path = dir.join("blob-benchmark.csv");
    tokio::fs::write(&csv_path, &csv).await?;
    println!("\nWrote {}", csv_path.display());

    Ok(())
}

/// Builds the Job for one cell of the matrix.
///
/// The container command is `persistcli` itself rather than a shell wrapping
/// it: the image carrying persistcli is distroless and has no `/bin/sh`, so a
/// shell form fails to start the container at all. That is also why each cell
/// is its own Job rather than a loop.
fn blob_job_manifest(
    job_name: &str,
    args: &crate::cli::BenchmarkArgs,
    target: &StoreTarget,
    size: u64,
    count: u64,
) -> Result<String> {
    let command = vec![
        "persistcli".to_string(),
        "bench".to_string(),
        "blob".to_string(),
        format!("--blob-uri={}", target.blob_uri),
        format!("--prefix=bench/{size}"),
        "--list-prefix=".to_string(),
        format!("--size-bytes={size}"),
        format!("--count={count}"),
        format!("--concurrency={}", args.concurrency),
        format!("--read-secs={}", args.read_secs),
        "--no-header".to_string(),
    ];

    let mut pod_spec = serde_json::json!({
        "restartPolicy": "Never",
        "nodeSelector": target.node_selector,
        "tolerations": target.tolerations,
        "containers": [{
            "name": "persistcli",
            "image": args.image,
            "command": command,
        }],
    });

    if let Some(account) = &target.service_account {
        pod_spec["serviceAccountName"] = serde_json::json!(account);
    }

    let manifest = serde_json::json!({
        "apiVersion": "batch/v1",
        "kind": "Job",
        "metadata": {
            "name": job_name,
            "namespace": target.namespace,
        },
        "spec": {
            // A benchmark that failed half way through has no usable result,
            // so let it fail rather than silently restart into a dirty store.
            "backoffLimit": 0,
            "template": {
                "spec": pod_spec,
            },
        },
    });

    serde_json::to_string_pretty(&manifest).context("failed to build the benchmark job manifest")
}
