use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use tokio::process::Command;

use crate::helpers::{
    ci_log_group, kubectl, read_tfvars, retry, run_cmd, run_cmd_output, write_lifecycle,
};
use crate::types::{CloudProvider, OryOutput, TerraformOutputs, TfVars};

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

        println!("\nVerifying Pod Security enforcement in namespace {instance_namespace}...");
        verify_pod_security_enforced(&kubeconfig, instance_namespace).await?;

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
        } else {
            let endpoint = outputs
                .load_balancer_endpoint()
                .context("Missing terraform output: load balancer endpoint")?;
            println!("\nVerifying Materialize SQL connectivity at {endpoint}...");
            verify_sql_connection(endpoint, &outputs).await?;
        }

        if let Some(ory) = outputs.ory() {
            println!(
                "\nVerifying the Ory stack in namespace {}...",
                ory.namespace
            );
            if let Err(e) = verify_ory(dir, &kubeconfig, ory).await {
                dump_ory_diagnostics(&kubeconfig, &ory.namespace).await;
                return Err(e);
            }
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

/// Best-effort diagnostic dump when verify_materialize_instance times out or
/// the pods check fails.
/// Each command's failure is logged but ignored so we always get the rest of
/// the output even if one section errors.
async fn dump_materialize_diagnostics(kubeconfig: &Path, namespace: &str, name: &str) {
    println!("\n--- diagnostics: Materialize CR did not become UpToDate ---");

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

    println!("\n--- end diagnostics ---");
}

/// Runs one diagnostic kubectl command, logging rather than returning its
/// failure so the rest of a dump still runs.
async fn run_section(label: &str, kubeconfig: &Path, args: &[&str]) {
    println!("\n>>> {label}");
    if let Err(e) = run_cmd(kubectl(kubeconfig).args(args)).await {
        println!("(diagnostic command failed: {e:#})");
    }
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

/// Asserts that the instance namespace rejects a privileged pod.
///
/// The Materialize pods coming up only shows they meet the restricted Pod
/// Security Standard, not that it is enforced. A server-side dry run goes
/// through admission without creating anything.
async fn verify_pod_security_enforced(kubeconfig: &Path, namespace: &str) -> Result<()> {
    let output = kubectl(kubeconfig)
        .args([
            "run",
            "pod-security-check",
            "-n",
            namespace,
            "--image=busybox",
            "--restart=Never",
            "--privileged",
            "--dry-run=server",
        ])
        .output()
        .await
        .context("Failed to execute command")?;
    let stderr = String::from_utf8_lossy(&output.stderr);
    if output.status.success() {
        bail!("a privileged pod was admitted to {namespace}");
    }
    if !stderr.contains("violates PodSecurity") {
        bail!("privileged pod was rejected, but not by Pod Security: {stderr}");
    }
    println!("  [ok] privileged pod rejected");
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
            with_port_forward(kubeconfig, namespace, service, 6875, |port| {
                sql_select_1("127.0.0.1", port, password)
            })
            .await
        },
    )
    .await
    .context("Failed to connect to Materialize via SQL after all retries")?;

    println!("  SQL query succeeded: {output}");
    Ok(())
}

/// Runs `f` with the local port of a `kubectl port-forward` to the given
/// service port, closing the tunnel afterwards.
async fn with_port_forward<T, F, Fut>(
    kubeconfig: &Path,
    namespace: &str,
    service: &str,
    remote_port: u16,
    f: F,
) -> Result<T>
where
    F: FnOnce(u16) -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    let (mut child, port) = spawn_port_forward(kubeconfig, namespace, service, remote_port).await?;
    let result = f(port).await;
    child.kill().await.ok();
    result
}

/// Spawns `kubectl port-forward` to the given service port and returns the
/// child process along with the local port. Port 0 lets the kernel pick a
/// free local port, which kubectl reports on stdout.
async fn spawn_port_forward(
    kubeconfig: &Path,
    namespace: &str,
    service: &str,
    remote_port: u16,
) -> Result<(tokio::process::Child, u16)> {
    use tokio::io::{AsyncBufReadExt, BufReader};

    let mut child = kubectl(kubeconfig)
        .args([
            "port-forward",
            &format!("svc/{service}"),
            &format!("0:{remote_port}"),
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
    println!("  Forwarding 127.0.0.1:{port} to {service}:{remote_port}");
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

/// cert-manager writes the issuing CA into every certificate Secret as
/// `ca.crt`, and all the Ory certificates come from the same issuer.
const ORY_CA_SECRET: &str = "hydra-tls";

/// Hydra's admin API Service, named by the Hydra chart. Plain HTTP.
const HYDRA_ADMIN_SERVICE: &str = "hydra-admin";
const HYDRA_ADMIN_PORT: u16 = 4445;

/// Health endpoints on each component's public port, checked after Hydra.
const ORY_HEALTH_PATHS: &[(&str, &str)] = &[
    ("kratos", "/health/ready"),
    ("ui", "/health/ready"),
    ("polis", "/api/health"),
];

/// Checks the Ory stack end to end from outside the cluster: every
/// deployment is up, Hydra serves discovery under the configured issuer,
/// Hydra Maester registered the Materialize OAuth2 client, Hydra issues a
/// token (which goes through the selfservice UI's token hook), and Kratos,
/// the UI and Polis report healthy. Every HTTPS call verifies the service's
/// certificate for its real hostname.
async fn verify_ory(dir: &Path, kubeconfig: &Path, ory: &OryOutput) -> Result<()> {
    const MAX_ATTEMPTS: u32 = 10;
    const INTERVAL: std::time::Duration = std::time::Duration::from_secs(6);
    let on_retry = |attempt: u32, err: &anyhow::Error| {
        println!(
            "  Attempt {attempt}/{MAX_ATTEMPTS}: {err:#}, retrying in {}s...",
            INTERVAL.as_secs()
        );
    };
    let ns = ory.namespace.as_str();

    run_cmd(kubectl(kubeconfig).args([
        "wait",
        "--for=condition=Available",
        "deployment",
        "--all",
        "-n",
        ns,
        "--timeout=600s",
    ]))
    .await
    .context("Ory deployments did not become Available within timeout")?;
    println!("  [ok] all deployments are Available");

    let ca = dir.join("ory-ca.crt");
    let ca_pem = run_cmd_output(kubectl(kubeconfig).args([
        "get",
        "secret",
        ORY_CA_SECRET,
        "-n",
        ns,
        "-o",
        r#"go-template={{index .data "ca.crt" | base64decode}}"#,
    ]))
    .await
    .context("Failed to read the Ory CA certificate")?;
    tokio::fs::write(&ca, format!("{ca_pem}\n")).await?;

    let hydra = ory.service("hydra")?;
    let discovery = retry(MAX_ATTEMPTS, INTERVAL, on_retry, || {
        with_port_forward(kubeconfig, ns, &hydra.name, 443, |port| {
            curl_json(
                &ca,
                &hydra.host,
                port,
                "/.well-known/openid-configuration",
                &[],
            )
        })
    })
    .await
    .context("Hydra discovery failed")?;
    let issuer = discovery["issuer"].as_str().unwrap_or_default();
    if issuer != ory.issuer {
        bail!(
            "Hydra advertises issuer {issuer:?}, expected {:?}",
            ory.issuer
        );
    }
    println!("  [ok] Hydra discovery advertises issuer {issuer}");

    let secret = ory.oauth2_client_secret_name.as_str();
    retry(30, INTERVAL, on_retry, || async {
        let client_id = run_cmd_output(kubectl(kubeconfig).args([
            "get",
            "secret",
            secret,
            "-n",
            ns,
            "--ignore-not-found",
            "-o",
            "jsonpath={.data.CLIENT_ID}",
        ]))
        .await?;
        if client_id.is_empty() {
            bail!("Hydra Maester has not written {secret} yet");
        }
        Ok(())
    })
    .await
    .context("Hydra Maester did not register the Materialize OAuth2 client")?;
    println!("  [ok] Hydra Maester wrote the OAuth2 client Secret {secret}");

    // Throwaway client_credentials clients from the admin API. The
    // selfservice UI's token hook gives machine tokens only to clients the
    // operator marked as managed, so the unmarked one proves the hook runs.
    let managed = create_hydra_client(kubeconfig, ns, true).await?;
    let token_args = ["-u", &managed, "-d", "grant_type=client_credentials"];
    let token = retry(MAX_ATTEMPTS, INTERVAL, on_retry, || {
        with_port_forward(kubeconfig, ns, &hydra.name, 443, |port| {
            curl_json(&ca, &hydra.host, port, "/oauth2/token", &token_args)
        })
    })
    .await
    .context("Hydra did not issue a client_credentials token to a managed client")?;
    if token["access_token"].as_str().is_none_or(str::is_empty) {
        bail!("Hydra's token response has no access_token");
    }
    println!("  [ok] Hydra issued a client_credentials token to a managed client");

    let unmanaged = create_hydra_client(kubeconfig, ns, false).await?;
    let token_args = ["-u", &unmanaged, "-d", "grant_type=client_credentials"];
    let status = retry(MAX_ATTEMPTS, INTERVAL, on_retry, || {
        with_port_forward(kubeconfig, ns, &hydra.name, 443, |port| {
            curl_status(&ca, &hydra.host, port, "/oauth2/token", &token_args)
        })
    })
    .await
    .context("Token request for an unmanaged client failed")?;
    if status != 403 {
        bail!("expected the token hook to refuse an unmanaged client with 403, got {status}");
    }
    println!("  [ok] the token hook refused a client that is not operator-managed");

    for &(component, path) in ORY_HEALTH_PATHS {
        let Some(svc) = ory.services.get(component) else {
            continue;
        };
        retry(MAX_ATTEMPTS, INTERVAL, on_retry, || {
            with_port_forward(kubeconfig, ns, &svc.name, 443, |port| {
                curl_https(&ca, &svc.host, port, path, &[])
            })
        })
        .await
        .with_context(|| format!("{component} is not healthy at {path}"))?;
        println!("  [ok] {component} is healthy");
    }

    Ok(())
}

/// Requests `https://<host>:<port><path>` through a port-forward on `port`.
/// `--resolve` sends the real hostname to 127.0.0.1, so the certificate is
/// checked against it and against `ca`. `extra` is passed to curl as is.
async fn curl_https(
    ca: &Path,
    host: &str,
    port: u16,
    path: &str,
    extra: &[&str],
) -> Result<String> {
    run_cmd_output(
        Command::new("curl")
            .args(["-sS", "--fail", "--max-time", "30", "--cacert"])
            .arg(ca)
            .arg("--resolve")
            .arg(format!("{host}:{port}:127.0.0.1"))
            .args(extra)
            .arg(format!("https://{host}:{port}{path}")),
    )
    .await
}

/// Like [`curl_https`], but returns the HTTP status instead of failing on
/// an error status.
async fn curl_status(ca: &Path, host: &str, port: u16, path: &str, extra: &[&str]) -> Result<u16> {
    let code = run_cmd_output(
        Command::new("curl")
            .args(["-sS", "-o", "/dev/null", "-w", "%{http_code}"])
            .args(["--max-time", "30", "--cacert"])
            .arg(ca)
            .arg("--resolve")
            .arg(format!("{host}:{port}:127.0.0.1"))
            .args(extra)
            .arg(format!("https://{host}:{port}{path}")),
    )
    .await?;
    code.parse()
        .with_context(|| format!("curl printed no HTTP status: {code:?}"))
}

/// Creates a `client_credentials` client through Hydra's admin API and
/// returns `client_id:client_secret`. `managed` sets the metadata marker the
/// selfservice UI's token hook trusts, as an operator's client would have.
async fn create_hydra_client(kubeconfig: &Path, ns: &str, managed: bool) -> Result<String> {
    let body = serde_json::json!({
        "client_name": if managed { "kind-ci-managed" } else { "kind-ci-unmanaged" },
        "grant_types": ["client_credentials"],
        "metadata": { "materialize_managed": managed },
    })
    .to_string();
    let client = retry(
        10,
        std::time::Duration::from_secs(6),
        |attempt, err| println!("  Attempt {attempt}/10: {err:#}, retrying in 6s..."),
        || {
            with_port_forward(
                kubeconfig,
                ns,
                HYDRA_ADMIN_SERVICE,
                HYDRA_ADMIN_PORT,
                |port| {
                    let body = body.as_str();
                    async move {
                        let out = run_cmd_output(Command::new("curl").args([
                            "-sS",
                            "--fail",
                            "--max-time",
                            "30",
                            "-H",
                            "Content-Type: application/json",
                            "-d",
                            body,
                            &format!("http://127.0.0.1:{port}/admin/clients"),
                        ]))
                        .await?;
                        serde_json::from_str::<serde_json::Value>(&out)
                            .context("Hydra admin returned invalid JSON")
                    }
                },
            )
        },
    )
    .await
    .context("Failed to create a Hydra OAuth2 client")?;
    let (Some(id), Some(secret)) = (
        client["client_id"].as_str(),
        client["client_secret"].as_str(),
    ) else {
        bail!("Hydra admin response has no client_id/client_secret");
    };
    Ok(format!("{id}:{secret}"))
}

async fn curl_json(
    ca: &Path,
    host: &str,
    port: u16,
    path: &str,
    extra: &[&str],
) -> Result<serde_json::Value> {
    let body = curl_https(ca, host, port, path, extra).await?;
    serde_json::from_str(&body).with_context(|| format!("{path} returned invalid JSON"))
}

async fn dump_ory_diagnostics(kubeconfig: &Path, namespace: &str) {
    println!("\n--- diagnostics: Ory stack ---");
    run_section(
        "kubectl get pods (Ory namespace)",
        kubeconfig,
        &["get", "pods", "-n", namespace, "-o", "wide"],
    )
    .await;
    run_section(
        "kubectl get events (Ory namespace)",
        kubeconfig,
        &["get", "events", "-n", namespace, "--sort-by=.lastTimestamp"],
    )
    .await;
    run_section(
        "kubectl logs (Ory namespace, last 50 lines per pod)",
        kubeconfig,
        &[
            "logs",
            "-n",
            namespace,
            "-l",
            "app.kubernetes.io/name",
            "--tail=50",
            "--all-containers",
            "--prefix",
            "--max-log-requests=20",
        ],
    )
    .await;
    println!("\n--- end diagnostics ---");
}
