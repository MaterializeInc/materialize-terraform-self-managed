use std::path::{Path, PathBuf};
use std::process::Stdio;

use anyhow::{Context, Result, bail};
use aws_sdk_s3::Client as S3Client;
use aws_sdk_s3::primitives::ByteStream;
use chrono::Utc;
use rand::distr;
use rand::distr::SampleString as _;
use tokio::process::Command;

use crate::types::TfVars;

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

/// Returns the project root directory (the git repo root).
pub fn project_root() -> Result<PathBuf> {
    let output = std::process::Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("Failed to run `git rev-parse --show-toplevel`")?;
    if !output.status.success() {
        bail!("Not inside a git repository");
    }
    let root = std::str::from_utf8(&output.stdout)
        .context("git output was not valid UTF-8")?
        .trim();
    Ok(PathBuf::from(root))
}

pub fn example_dir(provider: crate::types::CloudProvider) -> Result<PathBuf> {
    let root = project_root()?;
    let path = root.join(provider.dir_name()).join("examples/simple");
    if !path.exists() {
        bail!("Example directory does not exist: {}", path.display());
    }
    Ok(path)
}

pub fn runs_dir() -> Result<PathBuf> {
    Ok(project_root()?.join("test/runs"))
}

pub fn test_run_dir(test_run: &str) -> Result<PathBuf> {
    let path = runs_dir()?.join(test_run);
    if !path.exists() {
        bail!("Test run directory does not exist: {}", path.display());
    }
    Ok(path)
}

/// Reads the saved TfVars from a test run directory.
pub fn read_tfvars(dir: &Path) -> Result<TfVars> {
    let tfvars_path = dir.join("terraform.tfvars.json");
    let content = std::fs::read_to_string(&tfvars_path)
        .with_context(|| format!("Failed to read {}", tfvars_path.display()))?;
    serde_json::from_str(&content).context("Failed to parse terraform.tfvars.json")
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

const LIFECYCLE_FILE: &str = ".lifecycle";

pub async fn write_lifecycle(dir: &Path, phase: &str, status: &str) -> Result<()> {
    let path = dir.join(LIFECYCLE_FILE);
    tokio::fs::write(&path, format!("{phase} {status}\n")).await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// ID generation
// ---------------------------------------------------------------------------

/// A distribution that samples uniformly from a fixed set of characters.
struct Charset(&'static [u8]);

const LOWER_ALPHANUMERIC: Charset = Charset(b"0123456789abcdefghijklmnopqrstuvwxyz");
const LOWER_ALPHA: Charset = Charset(b"abcdefghijklmnopqrstuvwxyz");

impl distr::Distribution<char> for Charset {
    fn sample<R: rand::Rng + ?Sized>(&self, rng: &mut R) -> char {
        self.0[rng.random_range(0..self.0.len())] as char
    }
}

impl distr::SampleString for Charset {
    fn append_string<R: rand::Rng + ?Sized>(&self, rng: &mut R, s: &mut String, len: usize) {
        s.extend((0..len).map(|_| <Self as distr::Distribution<char>>::sample(self, rng)));
    }
}

/// Generates a test run ID like `t260319-a4bc2f`.
///
/// The ID is used as `name_prefix` in terraform, which AWS constrains to
/// max 38 chars and lowercase alphanumeric + hyphens only. We use a short
/// date (YYMMDD, 6 chars) and a 6-char lowercase alphanumeric suffix
/// (last char always a letter), totalling 15 chars, leaving plenty of room
/// for AWS resource name suffixes.
pub fn generate_test_run_id() -> String {
    let now = Utc::now();
    let date = now.format("%y%m%d");
    let mut rng = rand::rng();
    let mut suffix = LOWER_ALPHANUMERIC.sample_string(&mut rng, 5);
    LOWER_ALPHA.append_string(&mut rng, &mut suffix, 1);
    format!("t{date}-{suffix}")
}

// ---------------------------------------------------------------------------
// Command execution
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// GitHub Actions log grouping
// ---------------------------------------------------------------------------

fn is_ci() -> bool {
    std::env::var_os("CI").is_some()
}

/// Wraps an async block in GitHub Actions log grouping.
/// Outside CI this is a no-op passthrough.
pub async fn ci_log_group<F, Fut, T>(name: &str, f: F) -> Result<T>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    if is_ci() {
        println!("::group::{name}");
    }
    let result = f().await;
    if is_ci() {
        println!("::endgroup::");
    }
    result
}

// ---------------------------------------------------------------------------
// Command execution
// ---------------------------------------------------------------------------

pub async fn run_cmd(cmd: &mut Command) -> Result<()> {
    let status = cmd
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .await
        .context("Failed to execute command")?;
    if !status.success() {
        bail!("Command exited with status: {}", status);
    }
    Ok(())
}

pub async fn run_cmd_output(cmd: &mut Command) -> Result<String> {
    let output = cmd
        .stderr(Stdio::inherit())
        .output()
        .await
        .context("Failed to execute command")?;
    if !output.status.success() {
        bail!("Command exited with status: {}", output.status);
    }
    Ok(String::from_utf8(output.stdout)?.trim().to_string())
}

/// Retries an async operation until it succeeds or the maximum number of
/// attempts is exhausted. Delays `interval` between attempts. On each
/// failure the error is passed to `on_retry` for logging.
pub async fn retry<F, Fut, T>(
    max_attempts: u32,
    interval: std::time::Duration,
    mut on_retry: impl FnMut(u32, &anyhow::Error),
    mut f: F,
) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    let mut last_err = None;
    for attempt in 1..=max_attempts {
        match f().await {
            Ok(val) => return Ok(val),
            Err(e) => {
                if attempt < max_attempts {
                    on_retry(attempt, &e);
                    tokio::time::sleep(interval).await;
                }
                last_err = Some(e);
            }
        }
    }
    Err(last_err.unwrap())
}

pub fn kubectl(kubeconfig: &Path) -> Command {
    let mut cmd = Command::new("kubectl");
    cmd.arg("--kubeconfig").arg(kubeconfig);
    cmd
}

// ---------------------------------------------------------------------------
// AWS SDK config
// ---------------------------------------------------------------------------

/// Builds an AWS SDK config with the given region and optional profile.
pub async fn aws_sdk_config(region: &str, profile: Option<&str>) -> aws_config::SdkConfig {
    let mut loader = aws_config::defaults(aws_config::BehaviorVersion::latest())
        .region(aws_config::Region::new(region.to_owned()));
    if let Some(p) = profile {
        loader = loader.profile_name(p);
    }
    loader.load().await
}

// ---------------------------------------------------------------------------
// S3 backend helpers
// ---------------------------------------------------------------------------

/// Parsed S3 backend configuration from a `backend.tf` file.
pub struct S3Backend {
    pub bucket: String,
    pub region: String,
    pub profile: Option<String>,
    /// The key prefix (test run ID), extracted from the state key.
    pub key_prefix: String,
}

/// Reads `backend.tf` from the given directory and extracts the S3
/// configuration. Returns `None` if the file does not exist (local state).
pub fn read_s3_backend(dir: &Path) -> Result<Option<S3Backend>> {
    let path = dir.join("backend.tf");
    let content = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e).context("Failed to read backend.tf"),
    };

    let body: hcl_edit::structure::Body = content.parse().context("Failed to parse backend.tf")?;

    let terraform = body
        .get_blocks("terraform")
        .next()
        .context("backend.tf missing terraform block")?;

    let backend = terraform
        .body
        .get_blocks("backend")
        .find(|b| b.has_labels(&["s3"]))
        .context("backend.tf missing backend \"s3\" block")?;

    fn get_str<'a>(body: &'a hcl_edit::structure::Body, key: &str) -> Option<&'a str> {
        body.get_attribute(key)?.value.as_str()
    }

    let bucket = get_str(&backend.body, "bucket")
        .context("backend.tf missing bucket")?
        .to_string();
    let region = get_str(&backend.body, "region")
        .context("backend.tf missing region")?
        .to_string();
    let profile = get_str(&backend.body, "profile").map(|s| s.to_string());
    let key = get_str(&backend.body, "key").context("backend.tf missing key")?;
    let key_prefix = key
        .split('/')
        .next()
        .context("backend.tf key has no prefix")?
        .to_string();

    Ok(Some(S3Backend {
        bucket,
        region,
        profile,
        key_prefix,
    }))
}

/// Uploads `terraform.tfvars.json` to the S3 backend alongside the state
/// file, so that other commands or CI jobs can discover the tfvars for a
/// given test run.
pub async fn upload_tfvars_to_backend(dir: &Path) -> Result<()> {
    let backend = match read_s3_backend(dir)? {
        Some(b) => b,
        None => return Ok(()),
    };

    let src = dir.join("terraform.tfvars.json");
    let key = format!("{}/terraform.tfvars.json", backend.key_prefix);

    println!(
        "Uploading terraform.tfvars.json to s3://{}/{key}",
        backend.bucket
    );
    let config = aws_sdk_config(&backend.region, backend.profile.as_deref()).await;
    let client = S3Client::new(&config);
    let body = ByteStream::from_path(&src)
        .await
        .context("Failed to read terraform.tfvars.json")?;
    client
        .put_object()
        .bucket(&backend.bucket)
        .key(&key)
        .body(body)
        .send()
        .await
        .context("Failed to upload terraform.tfvars.json to S3")?;

    Ok(())
}

/// Deletes the remote state file and tfvars file from S3 for the given
/// test run directory. No-ops if no S3 backend is configured.
pub async fn delete_backend_state(dir: &Path) -> Result<()> {
    let backend = match read_s3_backend(dir)? {
        Some(b) => b,
        None => return Ok(()),
    };

    println!(
        "Deleting remote state from s3://{}/{}/",
        backend.bucket, backend.key_prefix
    );
    let config = aws_sdk_config(&backend.region, backend.profile.as_deref()).await;
    let client = S3Client::new(&config);

    let keys = [
        format!("{}/terraform.tfstate", backend.key_prefix),
        format!("{}/terraform.tfvars.json", backend.key_prefix),
    ];
    for key in &keys {
        // S3 DeleteObject is a no-op if the key doesn't exist.
        client
            .delete_object()
            .bucket(&backend.bucket)
            .key(key)
            .send()
            .await
            .with_context(|| format!("Failed to delete s3://{}/{key}", backend.bucket))?;
    }

    Ok(())
}
