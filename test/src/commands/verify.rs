use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use tokio::process::Command;

use crate::helpers::{
    ci_log_group, kubectl, read_tfvars, retry, run_cmd, run_cmd_output, write_lifecycle,
};
use crate::types::{CloudProvider, TerraformOutputs, TfVars};

/// Runs verification commands against an applied test environment.
pub async fn phase_verify(dir: &Path) -> Result<()> {
    ci_log_group("Verify", || async {
        write_lifecycle(dir, "verify", "started").await?;
        let tfvars = read_tfvars(dir)?;
        let provider = tfvars.cloud_provider();
        println!("Verifying test run...");

        let outputs_raw = run_cmd_output(
            Command::new("terraform")
                .args(["output", "-json"])
                .current_dir(dir),
        )
        .await
        .context("terraform output failed")?;

        let outputs: TerraformOutputs =
            serde_json::from_str(&outputs_raw).context("Failed to parse terraform output JSON")?;

        let instance_namespace = &outputs.materialize_instance_namespace.value;
        let instance_name = &outputs.materialize_instance_name.value;

        println!("\nConfiguring kubectl...");
        let kubeconfig = setup_kubeconfig(dir, provider, &tfvars, &outputs).await?;

        println!("\nVerifying Materialize instance...");
        verify_materialize_instance(&kubeconfig, instance_namespace, instance_name).await?;

        println!("\nVerifying pods in namespace {instance_namespace}...");
        if let Err(e) = verify_pods_running(&kubeconfig, instance_namespace).await {
            // The retry log only shows counts; the describe output has the
            // scheduling events explaining why a pod never became Running.
            dump_materialize_diagnostics(&kubeconfig, instance_namespace, instance_name).await;
            return Err(e);
        }

        if let Some(version) = tfvars.common().environmentd_version.as_deref() {
            println!("\nVerifying environmentd is running version {version}...");
            verify_environmentd_image(&kubeconfig, instance_namespace, version).await?;
        }

        println!("\nVerifying node-local-dns...");
        verify_node_local_dns(&kubeconfig, provider).await?;

        println!("\nVerifying the default DNS deployments were scaled down...");
        verify_default_dns_scaled_down(&kubeconfig, provider).await?;

        if provider == CloudProvider::Kind {
            println!("\nVerifying Materialize SQL connectivity via port-forward...");
            verify_sql_connection_via_port_forward(&kubeconfig, instance_namespace, &outputs)
                .await?;
        } else if let Some(endpoint) = outputs.load_balancer_endpoint() {
            println!("\nVerifying Materialize SQL connectivity at {endpoint}...");
            verify_sql_connection(endpoint, &outputs).await?;
        } else {
            println!("\nSkipping SQL connectivity check (no load balancer endpoint found).");
        }

        write_lifecycle(dir, "verify", "completed").await?;
        println!("\nAll verifications passed!");
        Ok(())
    })
    .await
}

async fn setup_kubeconfig(
    dir: &Path,
    provider: CloudProvider,
    tfvars: &TfVars,
    outputs: &TerraformOutputs,
) -> Result<PathBuf> {
    let kubeconfig = dir.join("kubeconfig");
    // The kind cluster is named after the test run rather than a terraform
    // output, since terraform does not create it.
    let cluster_name = match provider {
        CloudProvider::Kind => dir.file_name().unwrap().to_string_lossy().into_owned(),
        _ => outputs.cluster_name(provider)?.to_string(),
    };
    let cluster_name = cluster_name.as_str();
    match tfvars {
        TfVars::Kind { .. } => {
            run_cmd(
                Command::new("kind")
                    .args(["export", "kubeconfig", "--name", cluster_name])
                    .arg("--kubeconfig")
                    .arg(&kubeconfig),
            )
            .await?;
        }
        TfVars::Aws {
            aws_region,
            aws_profile,
            ..
        } => {
            run_cmd(
                Command::new("aws")
                    .args([
                        "eks",
                        "update-kubeconfig",
                        "--name",
                        cluster_name,
                        "--region",
                        aws_region,
                        "--profile",
                        aws_profile,
                    ])
                    .env("KUBECONFIG", &kubeconfig),
            )
            .await?;
        }
        TfVars::Gcp {
            region, project_id, ..
        } => {
            run_cmd(
                Command::new("gcloud")
                    .args([
                        "container",
                        "clusters",
                        "get-credentials",
                        cluster_name,
                        "--region",
                        region,
                        "--project",
                        project_id,
                    ])
                    .env("KUBECONFIG", &kubeconfig),
            )
            .await?;
        }
        TfVars::Azure {
            resource_group_name,
            ..
        } => {
            run_cmd(
                Command::new("az")
                    .args([
                        "aks",
                        "get-credentials",
                        "--resource-group",
                        resource_group_name,
                        "--name",
                        cluster_name,
                        "--overwrite-existing",
                    ])
                    .env("KUBECONFIG", &kubeconfig),
            )
            .await?;
        }
    }
    println!("  Wrote {}", kubeconfig.display());
    Ok(kubeconfig)
}

async fn verify_materialize_instance(kubeconfig: &Path, namespace: &str, name: &str) -> Result<()> {
    let result = run_cmd(kubectl(kubeconfig).args([
        "wait",
        "--for=jsonpath={.status.conditions[?(@.type==\"UpToDate\")].status}=True",
        &format!("materialize/{name}"),
        "-n",
        namespace,
        "--timeout=600s",
    ]))
    .await;

    if let Err(e) = result {
        dump_materialize_diagnostics(kubeconfig, namespace, name).await;
        return Err(e).context("Materialize instance did not become UpToDate within timeout");
    }

    println!("  Materialize instance {name} is UpToDate.");
    Ok(())
}

/// Best-effort diagnostic dump when verify_materialize_instance times out.
/// Each command's failure is logged but ignored so we always get the rest of
/// the output even if one section errors.
async fn dump_materialize_diagnostics(kubeconfig: &Path, namespace: &str, name: &str) {
    println!("\n--- diagnostics: Materialize CR did not become UpToDate ---");

    async fn run_section(label: &str, kubeconfig: &Path, args: &[&str]) {
        println!("\n>>> {label}");
        if let Err(e) = run_cmd(kubectl(kubeconfig).args(args)).await {
            println!("(diagnostic command failed: {e:#})");
        }
    }

    let materialize_ref = format!("materialize/{name}");
    run_section(
        "kubectl describe materialize",
        kubeconfig,
        &["describe", &materialize_ref, "-n", namespace],
    )
    .await;
    run_section(
        "kubectl get pods (instance namespace)",
        kubeconfig,
        &["get", "pods", "-n", namespace, "-o", "wide"],
    )
    .await;
    run_section(
        "kubectl get pods (operator namespace)",
        kubeconfig,
        &["get", "pods", "-n", "materialize", "-o", "wide"],
    )
    .await;
    run_section(
        "kubectl logs (materialize-operator, last 300 lines)",
        kubeconfig,
        &[
            "logs",
            "-n",
            "materialize",
            "-l",
            "app.kubernetes.io/name=materialize-operator",
            "--tail=300",
            "--all-containers",
        ],
    )
    .await;
    run_section(
        "kubectl describe pods (instance namespace)",
        kubeconfig,
        &["describe", "pods", "-n", namespace],
    )
    .await;
    run_section(
        "kubectl get networkpolicy (all namespaces)",
        kubeconfig,
        &["get", "networkpolicy", "-A", "-o", "yaml"],
    )
    .await;
    run_section(
        "kubectl get svc,endpoints (instance namespace)",
        kubeconfig,
        &["get", "svc,endpoints", "-n", namespace, "-o", "wide"],
    )
    .await;

    // Probe environmentd:6876 from a pod scheduled into the operator namespace.
    // That pod inherits the same egress NetworkPolicies as the orchestratord, so
    // the curl exit / verbose output disambiguates the failure mode (timeout =>
    // NetworkPolicy or SG drop; refused => no listener; TLS error => cert
    // mismatch). Best-effort; if anything in the probe fails we just log and
    // move on.
    if let Ok(resource_id) = run_cmd_output(kubectl(kubeconfig).args([
        "get",
        &format!("materialize/{name}"),
        "-n",
        namespace,
        "-o",
        "jsonpath={.status.resourceId}",
    ]))
    .await
        && !resource_id.is_empty()
    {
        let target = format!(
            "https://mz{resource_id}-environmentd-1.{namespace}.svc.cluster.local:6876/api/login"
        );
        let probe_name = format!("verify-probe-{resource_id}");
        println!("\n>>> curl probe from operator namespace -> {target}");
        if let Err(e) = run_cmd(kubectl(kubeconfig).args([
            "run",
            &probe_name,
            "--rm",
            "--restart=Never",
            "-i",
            "--image=curlimages/curl:latest",
            "--namespace=materialize",
            "--command",
            "--",
            "curl",
            "-v",
            "-k",
            "--max-time",
            "15",
            &target,
        ]))
        .await
        {
            println!("(probe failed: {e:#})");
        }
    }

    println!("\n--- end diagnostics ---");
}

/// The expected pod types and their minimum counts in the materialize namespace.
const EXPECTED_PODS: &[(&str, usize)] = &[
    ("environmentd", 1),
    ("console", 2),
    ("balancerd", 2),
    ("cluster-u1", 1),
    ("cluster-s2", 1),
];

async fn verify_pods_running(kubeconfig: &Path, namespace: &str) -> Result<()> {
    const MAX_ATTEMPTS: u32 = 60;
    const INTERVAL: std::time::Duration = std::time::Duration::from_secs(10);

    retry(
        MAX_ATTEMPTS,
        INTERVAL,
        |attempt, err| {
            println!(
                "  Attempt {attempt}/{MAX_ATTEMPTS}: {err:#}, retrying in {}s...",
                INTERVAL.as_secs()
            );
        },
        || check_expected_pods(kubeconfig, namespace),
    )
    .await
    .context("Not all expected pods became Running within timeout")?;

    println!("  All expected pods are running.");
    Ok(())
}

async fn check_expected_pods(kubeconfig: &Path, namespace: &str) -> Result<()> {
    let output = run_cmd_output(kubectl(kubeconfig).args([
        "get",
        "pods",
        "-n",
        namespace,
        "-o",
        "jsonpath={range .items[*]}{.metadata.name} {.status.phase}{'\\n'}{end}",
    ]))
    .await?;

    let pods: Vec<(&str, &str)> = output
        .lines()
        .filter_map(|line| {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                Some((parts[0], parts[1]))
            } else {
                None
            }
        })
        .collect();

    for &(pod_type, min_count) in EXPECTED_PODS {
        let running = pods
            .iter()
            .filter(|(name, phase)| name.contains(pod_type) && *phase == "Running")
            .count();
        if running < min_count {
            bail!("expected at least {min_count} running {pod_type} pod(s), found {running}");
        }
    }

    for (name, phase) in &pods {
        // Pods outside EXPECTED_PODS, and surplus pods of an expected type
        // (e.g. the incoming ReplicaSet during a rollout), are listed but do
        // not gate the check -- so only mark the Running ones ok.
        let mark = if *phase == "Running" { "ok" } else { "--" };
        println!("  [{mark}] {name}: {phase}");
    }
    Ok(())
}

/// Asserts that the running environmentd pods use the image tag requested via
/// `--environmentd-version`.
///
/// Without this, an override that fails to reach the terraform module leaves
/// the run on the module's default version and every other check still passes,
/// so a test of a specific build silently becomes a test of a different one.
async fn verify_environmentd_image(
    kubeconfig: &Path,
    namespace: &str,
    expected_version: &str,
) -> Result<()> {
    let output = run_cmd_output(kubectl(kubeconfig).args([
        "get",
        "pods",
        "-n",
        namespace,
        "-o",
        "jsonpath={range .items[*]}{.metadata.name} {.status.phase} {.spec.containers[0].image}{'\\n'}{end}",
    ]))
    .await?;

    let expected_suffix = format!(":{expected_version}");
    let mut checked = 0;
    for line in output.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        let [name, phase, image] = parts[..] else {
            continue;
        };
        if !name.contains("environmentd") || phase != "Running" {
            continue;
        }
        if !image.ends_with(&expected_suffix) {
            bail!("{name} runs image {image}, expected version {expected_version}");
        }
        println!("  [ok] {name}: {image}");
        checked += 1;
    }

    if checked == 0 {
        bail!("found no running environmentd pod to check the image version of");
    }
    Ok(())
}

/// Waits for the node-local-dns DaemonSet to be ready. It is deployed by the
/// node-local-dns helm module on AWS and by the NodeLocal DNSCache addon on
/// GCP; AKS has no supported node-local DNS option (see azure/README.md).
async fn verify_node_local_dns(kubeconfig: &Path, provider: CloudProvider) -> Result<()> {
    match provider {
        CloudProvider::Azure => {
            println!("  Skipping node-local-dns check (not supported on AKS).");
            return Ok(());
        }
        CloudProvider::Kind => {
            println!("  Skipping node-local-dns check (not deployed on kind).");
            return Ok(());
        }
        _ => {}
    }

    const MAX_ATTEMPTS: u32 = 10;
    const INTERVAL: std::time::Duration = std::time::Duration::from_secs(10);

    retry(
        MAX_ATTEMPTS,
        INTERVAL,
        |attempt, err| {
            println!(
                "  Attempt {attempt}/{MAX_ATTEMPTS}: {err:#}, retrying in {}s...",
                INTERVAL.as_secs()
            );
        },
        || async {
            run_cmd(kubectl(kubeconfig).args([
                "rollout",
                "status",
                "daemonset/node-local-dns",
                "-n",
                "kube-system",
                "--timeout=60s",
            ]))
            .await
        },
    )
    .await
    .context("node-local-dns DaemonSet did not become ready within timeout")?;

    println!("  node-local-dns DaemonSet is ready.");
    Ok(())
}

/// The kube-system deployments that kubernetes/modules/coredns scales to zero,
/// so that only its custom CoreDNS serves DNS. Names differ per provider and
/// match what {provider}/examples/simple passes to the module.
///
/// AWS lists no autoscaler on purpose: EKS ships no CoreDNS autoscaler
/// deployment, so aws/examples/simple sets
/// `disable_default_coredns_autoscaler = false` and nothing scales it.
fn scaled_down_dns_deployments(provider: CloudProvider) -> &'static [&'static str] {
    match provider {
        CloudProvider::Aws => &["coredns"],
        CloudProvider::Gcp => &["kube-dns", "kube-dns-autoscaler"],
        CloudProvider::Azure => &["coredns", "coredns-autoscaler"],
        // kind keeps its stock CoreDNS; the coredns module is not applied.
        CloudProvider::Kind => &[],
    }
}

/// Checks that the provider's default DNS deployments really are at zero
/// replicas.
///
/// The scale-down runs in a local-exec provisioner, and it treats a missing
/// deployment as success, so a wrong deployment name leaves the default DNS
/// running and still reports a clean apply. Nothing else here would notice:
/// Materialize comes up fine with two DNS stacks. Reading the replica count
/// back is what turns that silent no-op into a failure.
///
/// A deployment that does not exist at all is accepted, matching the
/// provisioner's own contract — the provider may never have created it.
async fn verify_default_dns_scaled_down(kubeconfig: &Path, provider: CloudProvider) -> Result<()> {
    let deployments = scaled_down_dns_deployments(provider);
    if deployments.is_empty() {
        println!(
            "  Skipping default-DNS scale-down check (the coredns module is not applied on kind)."
        );
        return Ok(());
    }
    for deployment in deployments {
        // --ignore-not-found keeps an absent deployment on the success path,
        // so it is distinguishable from a genuine kubectl failure.
        let replicas = run_cmd_output(kubectl(kubeconfig).args([
            "get",
            "deployment",
            deployment,
            "-n",
            "kube-system",
            "--ignore-not-found",
            "-o",
            "jsonpath={.spec.replicas}",
        ]))
        .await
        .with_context(|| format!("Failed to read replica count for {deployment}"))?;

        match replicas.as_str() {
            "" => println!("  {deployment} does not exist, nothing to scale down."),
            "0" => println!("  [ok] {deployment} is scaled to 0 replicas."),
            other => bail!(
                "expected deployment {deployment} in kube-system to be scaled to 0 \
                 replicas, found {other}. The default DNS stack is still running \
                 alongside the custom CoreDNS."
            ),
        }
    }

    Ok(())
}

/// SQL connectivity check for kind, where there is no load balancer: forwards
/// a local port to the balancerd service and connects through it.
///
/// The whole tunnel is set up fresh on every attempt: balancerd can be Running
/// but not yet Ready (no service endpoints, so port-forward fails
/// immediately), and an established tunnel dies if kubectl loses the pod
/// connection.
async fn verify_sql_connection_via_port_forward(
    kubeconfig: &Path,
    namespace: &str,
    outputs: &TerraformOutputs,
) -> Result<()> {
    let service = outputs
        .balancerd_service_name
        .as_ref()
        .map(|o| o.value.as_str())
        .context("Missing terraform output: balancerd_service_name")?;
    let password = outputs.mz_password()?;

    const MAX_ATTEMPTS: u32 = 20;
    const INTERVAL: std::time::Duration = std::time::Duration::from_secs(15);

    let output = retry(
        MAX_ATTEMPTS,
        INTERVAL,
        |attempt, err| {
            println!(
                "  Attempt {attempt}/{MAX_ATTEMPTS}: {err:#}, retrying in {}s...",
                INTERVAL.as_secs()
            );
        },
        || async {
            let (mut child, port) = spawn_port_forward(kubeconfig, namespace, service).await?;
            let result = sql_select_1("127.0.0.1", port, password).await;
            child.kill().await.ok();
            result
        },
    )
    .await
    .context("Failed to connect to Materialize via SQL after all retries")?;

    println!("  SQL query succeeded: {output}");
    Ok(())
}

/// Spawns `kubectl port-forward` to the given service's SQL port and returns
/// the child process along with the local port. Port 0 lets the kernel pick a
/// free local port, which kubectl reports on stdout.
async fn spawn_port_forward(
    kubeconfig: &Path,
    namespace: &str,
    service: &str,
) -> Result<(tokio::process::Child, u16)> {
    use tokio::io::{AsyncBufReadExt, BufReader};

    let mut child = kubectl(kubeconfig)
        .args([
            "port-forward",
            &format!("svc/{service}"),
            "0:6875",
            "-n",
            namespace,
        ])
        .stdout(std::process::Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .context("Failed to spawn kubectl port-forward")?;

    // First line looks like: "Forwarding from 127.0.0.1:52341 -> 6875".
    // Borrow stdout rather than take it: dropping the pipe would kill
    // kubectl with EPIPE as soon as it writes its next line.
    let stdout = child
        .stdout
        .as_mut()
        .context("port-forward has no stdout")?;
    let mut lines = BufReader::new(stdout).lines();
    let line = tokio::time::timeout(std::time::Duration::from_secs(60), lines.next_line())
        .await
        .context("Timed out waiting for kubectl port-forward to start")??
        .context("kubectl port-forward exited without output")?;
    let port: u16 = line
        .split(" -> ")
        .next()
        .and_then(|addr| addr.rsplit(':').next())
        .and_then(|p| p.parse().ok())
        .with_context(|| format!("Could not parse port-forward output: {line}"))?;
    println!("  Forwarding 127.0.0.1:{port} to {service}:6875");
    Ok((child, port))
}

async fn verify_sql_connection(endpoint: &str, outputs: &TerraformOutputs) -> Result<()> {
    let password = outputs.mz_password()?;

    const MAX_ATTEMPTS: u32 = 20;
    const INTERVAL: std::time::Duration = std::time::Duration::from_secs(15);

    let output = retry(
        MAX_ATTEMPTS,
        INTERVAL,
        |attempt, _| {
            println!(
                "  Attempt {attempt}/{MAX_ATTEMPTS} failed, retrying in {}s...",
                INTERVAL.as_secs()
            );
        },
        || sql_select_1(endpoint, 6875, password),
    )
    .await
    .context("Failed to connect to Materialize via SQL after all retries")?;

    println!("  SQL query succeeded: {output}");
    Ok(())
}

/// A single `SELECT 1` against Materialize via psql.
async fn sql_select_1(host: &str, port: u16, password: &str) -> Result<String> {
    run_cmd_output(
        Command::new("psql")
            .args([
                "-h",
                host,
                "-p",
                &port.to_string(),
                "-U",
                "mz_system",
                "-d",
                "materialize",
                "-c",
                "SELECT 1",
            ])
            .env("PGPASSWORD", password)
            .env("PGCONNECT_TIMEOUT", "30")
            .env("PGSSLMODE", "require"),
    )
    .await
}
