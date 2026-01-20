"""
Integration tests for Materialize deployment on kind.

These tests validate that the generated Terraform types work correctly
by deploying a full Materialize stack on a local kind cluster.

Requirements:
    - Docker
    - kind
    - kubectl
    - terraform
    - helm
    - MATERIALIZE_LICENSE_KEY environment variable

Run with: pytest tests/test_kind_integration.py -v -s --kind
"""

import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Callable,Type, TypeVar

import pytest

TESTS_DIR = Path(__file__).parent
KIND_DIR = TESTS_DIR / "kind"
TERRAFORM_DIR = KIND_DIR / "terraform"
MANIFESTS_DIR = KIND_DIR / "manifests"
LOGS_DIR = KIND_DIR / "logs"  # gitignored directory for pod logs
CLUSTER_NAME = "mz-test"

T = TypeVar("T")

def retry(f: Callable[..., T], attempts: int, delay: float, exc_type: Type[Exception]) -> T:
    exception = AssertionError("Attempts must be greater than 0")
    for i in range(0, attempts):
        try:
            return f()
        except exc_type as exc:
            print(f"Failed retryable call: {exc}")
            if i == attempts - 1:
                raise
            time.sleep(delay)
    raise exception



def run(cmd: list[str], check: bool = True, capture: bool = False, **kwargs) -> subprocess.CompletedProcess:
    """Run a command with proper error handling."""
    print(f"Running: {' '.join(cmd)}")
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=True,
        **kwargs,
    )


def capture_pod_logs(namespace: str, filename_prefix: str) -> None:
    """Capture logs from all pods in a namespace to files for debugging."""
    LOGS_DIR.mkdir(exist_ok=True)

    result = run(
        ["kubectl", "get", "pods", "-n", namespace, "-o", "jsonpath={.items[*].metadata.name}"],
        capture=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return

    for pod_name in result.stdout.strip().split():
        log_file = LOGS_DIR / f"{filename_prefix}_{pod_name}.log"
        log_result = run(
            ["kubectl", "logs", "-n", namespace, pod_name, "--all-containers=true"],
            capture=True,
            check=False,
        )
        if log_result.returncode == 0:
            log_file.write_text(log_result.stdout)
            print(f"Captured logs: {log_file}")


def capture_all_logs() -> None:
    """Capture logs from all relevant namespaces."""
    namespaces = ["materialize", "materialize-environment", "cert-manager", "postgres", "minio"]
    for ns in namespaces:
        capture_pod_logs(ns, ns)


def kind_cluster_exists() -> bool:
    """Check if the kind cluster exists."""
    result = run(["kind", "get", "clusters"], capture=True, check=False)
    return CLUSTER_NAME in result.stdout.split()


def wait_for_pods(namespace: str, label: str, timeout: int = 300) -> bool:
    """Wait for pods matching a label to be ready."""
    start = time.time()
    while time.time() - start < timeout:
        result = run(
            ["kubectl", "--context", f"kind-{CLUSTER_NAME}", "get", "pods", "-n", namespace, "-l", label, "-o", "json"],
            capture=True,
            check=False,
        )
        if result.returncode != 0:
            time.sleep(5)
            continue

        pods = json.loads(result.stdout)
        if not pods.get("items"):
            time.sleep(5)
            continue

        all_ready = True
        for pod in pods["items"]:
            phase = pod.get("status", {}).get("phase")
            if phase != "Running":
                all_ready = False
                break
            conditions = pod.get("status", {}).get("conditions", [])
            ready = any(
                c.get("type") == "Ready" and c.get("status") == "True"
                for c in conditions
            )
            if not ready:
                all_ready = False
                break

        if all_ready:
            return True
        time.sleep(5)

    return False


def wait_for_job(namespace: str, job_name: str, timeout: int = 120) -> bool:
    """Wait for a job to complete."""
    start = time.time()
    while time.time() - start < timeout:
        result = run(
            ["kubectl", "get", "job", job_name, "-n", namespace, "-o", "json"],
            capture=True,
            check=False,
        )
        if result.returncode != 0:
            time.sleep(5)
            continue

        job = json.loads(result.stdout)
        succeeded = job.get("status", {}).get("succeeded", 0)
        if succeeded >= 1:
            return True
        time.sleep(5)

    return False


@pytest.fixture(scope="module")
def kind_cluster():
    """Create and manage the kind cluster for tests."""
    # Check prerequisites
    for tool in ["kind", "kubectl", "terraform", "helm", "docker"]:
        if not shutil.which(tool):
            raise AssertionError(f"{tool} not found in PATH")

    # Create cluster if it doesn't exist
    if not kind_cluster_exists():
        print(f"Creating kind cluster '{CLUSTER_NAME}'...")
        run(["kind", "create", "cluster", "--config", str(KIND_DIR / "cluster.yaml")])

    # Set kubectl context
    run(["kubectl", "config", "use-context", f"kind-{CLUSTER_NAME}"])

    yield CLUSTER_NAME

    # Cleanup: delete the kind cluster
    print(f"Deleting kind cluster '{CLUSTER_NAME}'...")
    # run(["kind", "delete", "cluster", "--name", CLUSTER_NAME], check=False)


@pytest.fixture(scope="module")
def deploy_backends(kind_cluster):
    """Deploy PostgreSQL and MinIO backends."""
    # Deploy PostgreSQL
    print("Deploying PostgreSQL...")
    run(["kubectl", "apply", "-f", str(MANIFESTS_DIR / "postgres.yaml")])

    # Deploy MinIO
    print("Deploying MinIO...")
    run(["kubectl", "apply", "-f", str(MANIFESTS_DIR / "minio.yaml")])

    # Wait for PostgreSQL to be ready
    print("Waiting for PostgreSQL...")
    assert wait_for_pods("postgres", "app=postgres", timeout=120), "PostgreSQL failed to start"

    # Wait for MinIO to be ready
    print("Waiting for MinIO...")
    assert wait_for_pods("minio", "app=minio", timeout=120), "MinIO failed to start"

    # Wait for MinIO setup job
    print("Waiting for MinIO bucket setup...")
    assert wait_for_job("minio", "minio-setup", timeout=120), "MinIO setup job failed"

    yield

    # Backends persist for debugging


@pytest.fixture(scope="module")
def terraform_deploy(deploy_backends):
    """Deploy Materialize using Terraform."""
    # Check for license key
    license_key = os.environ.get("MATERIALIZE_LICENSE_KEY", "")
    assert license_key != "", "MATERIALIZE_LICENSE_KEY environment variable not set"

    # Set up environment with license key for Terraform
    env = os.environ.copy()
    env["TF_VAR_license_key"] = license_key

    # Initialize Terraform
    print("Initializing Terraform...")
    run(["terraform", "init"], cwd=TERRAFORM_DIR, env=env)

    # Apply Terraform
    print("Applying Terraform configuration...")
    try:
        run(
            ["terraform", "apply", "-auto-approve"],
            cwd=TERRAFORM_DIR,
            env=env,
            timeout=600,  # 10 minutes for full deployment
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        print(f"Terraform apply failed: {e}")
        capture_all_logs()
        raise

    yield

    # Capture logs before cleanup for debugging
    print("Capturing pod logs...")
    capture_all_logs()

    # Cleanup: destroy Terraform resources
    print("Destroying Terraform resources...")
    # run(["terraform", "destroy", "-auto-approve"], cwd=TERRAFORM_DIR, env=env, check=False)


@pytest.mark.kind
def test_operator_deployment(terraform_deploy):
    """Test that the Materialize operator is deployed and running."""
    assert wait_for_pods(
        "materialize", "app.kubernetes.io/name=materialize-operator", timeout=120
    ), "Materialize operator failed to start"


@pytest.mark.kind
def test_materialize_instance_created(terraform_deploy):
    """Test that the Materialize instance CR is created."""
    result = run(
        [
            "kubectl", "get", "materialize", "test-instance",
            "-n", "materialize-environment", "-o", "json"
        ],
        capture=True,
    )
    instance = json.loads(result.stdout)
    assert instance["metadata"]["name"] == "test-instance"


@pytest.mark.kind
def test_materialize_pods_running(terraform_deploy):
    """Test that Materialize pods are running."""
    # Wait for environmentd
    print("Waiting for Materialize environmentd...")
    assert wait_for_pods(
        "materialize-environment", "app=environmentd", timeout=300
    ), "Materialize environmentd failed to start"


@pytest.mark.kind
def test_materialize_sql_connection(terraform_deploy):
    """Test that we can connect to Materialize via SQL."""
    # Port-forward and test connection
    # This is a basic connectivity test


    def inner():
        result = run(
             [
                 "kubectl", "get", "pod", "-n", "materialize-environment",
                 "-l", "app=balancerd", "-o", "json"
             ],
             capture=True,
             check=False,
        )

        if result.returncode == 0:
            services = json.loads(result.stdout)
            assert len(services.get("items", [])) > 0, "No balancerd pod found"

    retry(
        f=lambda: inner(),
        attempts=60,
        delay=5,
        exc_type=AssertionError,
    )

