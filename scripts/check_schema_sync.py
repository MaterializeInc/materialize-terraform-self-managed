#!/usr/bin/env python3
"""
Check that Terraform type definitions are in sync with upstream Materialize schemas.

This script verifies that the CRD and Helm schemas are accessible for the
configured Materialize version and that the generated types are up to date.

Usage:
    python scripts/check_schema_sync.py [--version VERSION]

Exit codes:
    0: All checks passed
    1: Schema not accessible or types out of sync
"""

import argparse
import json
import subprocess
import sys
import tempfile
import filecmp
from pathlib import Path
from urllib.request import urlopen
from urllib.error import URLError

try:
    import yaml
except ImportError:
    print(
        "Error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr
    )
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent

# Import the generation functions from the main script
sys.path.insert(0, str(SCRIPT_DIR))
from generate_terraform_types import (  # noqa: E402
    get_version_from_source,
    generate_crd_type_block,
    generate_helm_type_block,
    write_crd_variables_file,
    write_helm_variables_file,
    write_example_override_variables_file,
    MATERIALIZE_INSTANCE_DIR,
    AWS_OPERATOR_DIR,
    AZURE_OPERATOR_DIR,
    GCP_OPERATOR_DIR,
    AWS_EXAMPLE_DIR,
    AZURE_EXAMPLE_DIR,
    GCP_EXAMPLE_DIR,
)


def fetch_url(url: str) -> str:
    """Fetch content from a URL."""
    try:
        with urlopen(url) as response:
            return response.read().decode("utf-8")
    except URLError:
        return None


def check_schema_accessible(version: str) -> tuple[bool, bool]:
    """Check if CRD and Helm schemas are accessible for the given version."""
    base_url = f"https://raw.githubusercontent.com/MaterializeInc/materialize/{version}"
    crd_url = f"{base_url}/doc/user/data/self_managed/materialize_crd_descriptions.json"
    helm_url = f"{base_url}/misc/helm-charts/operator/values.yaml"

    print(f"Checking CRD schema at: {crd_url}")
    crd_content = fetch_url(crd_url)
    crd_ok = crd_content is not None
    print(f"  {'OK' if crd_ok else 'FAILED'}")

    print(f"Checking Helm values at: {helm_url}")
    helm_content = fetch_url(helm_url)
    helm_ok = helm_content is not None
    print(f"  {'OK' if helm_ok else 'FAILED'}")

    return crd_ok, helm_ok, crd_content, helm_content


def terraform_fmt(path: Path) -> None:
    """Run terraform fmt on a file or directory."""
    try:
        subprocess.run(
            ["terraform", "fmt", str(path)],
            check=True,
            capture_output=True,
        )
    except FileNotFoundError:
        # terraform not installed, skip formatting
        pass
    except subprocess.CalledProcessError:
        # formatting failed, skip
        pass


def check_types_in_sync(crd_content: str, helm_content: str) -> bool:
    """Check if generated types match what would be generated from current schemas."""
    crd_json = json.loads(crd_content)
    helm_yaml = yaml.safe_load(helm_content)

    crd_type_block = generate_crd_type_block(crd_json)
    helm_type_block = generate_helm_type_block(helm_yaml)

    all_in_sync = True

    # Check each file by generating to a temp location and comparing
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        # Check CRD variables
        tmp_crd_dir = tmpdir / "crd"
        tmp_crd_dir.mkdir()
        write_crd_variables_file(tmp_crd_dir, crd_type_block)
        tmp_crd = tmp_crd_dir / "crd_variables.tf"
        terraform_fmt(tmp_crd)

        actual_crd = MATERIALIZE_INSTANCE_DIR / "crd_variables.tf"

        if actual_crd.exists():
            if not filecmp.cmp(actual_crd, tmp_crd, shallow=False):
                print(f"OUT OF SYNC: {actual_crd}")
                all_in_sync = False
            else:
                print(f"In sync: {actual_crd}")
        else:
            print(f"MISSING: {actual_crd}")
            all_in_sync = False

        # Check Helm variables for each operator module
        for operator_dir in [AWS_OPERATOR_DIR, AZURE_OPERATOR_DIR, GCP_OPERATOR_DIR]:
            tmp_helm_dir = tmpdir / f"helm_{operator_dir.parent.parent.name}"
            tmp_helm_dir.mkdir()
            write_helm_variables_file(tmp_helm_dir, helm_type_block)
            tmp_helm = tmp_helm_dir / "helm_variables.tf"
            terraform_fmt(tmp_helm)

            actual_helm = operator_dir / "helm_variables.tf"

            if actual_helm.exists():
                if not filecmp.cmp(actual_helm, tmp_helm, shallow=False):
                    print(f"OUT OF SYNC: {actual_helm}")
                    all_in_sync = False
                else:
                    print(f"In sync: {actual_helm}")
            else:
                print(f"MISSING: {actual_helm}")
                all_in_sync = False

        # Check example override variables
        for example_dir in [AWS_EXAMPLE_DIR, AZURE_EXAMPLE_DIR, GCP_EXAMPLE_DIR]:
            tmp_example_dir = tmpdir / f"example_{example_dir.parent.parent.name}"
            tmp_example_dir.mkdir()
            write_example_override_variables_file(
                tmp_example_dir, helm_type_block, crd_type_block
            )
            tmp_override = tmp_example_dir / "override_variables.tf"
            terraform_fmt(tmp_override)

            actual_override = example_dir / "override_variables.tf"

            if actual_override.exists():
                if not filecmp.cmp(actual_override, tmp_override, shallow=False):
                    print(f"OUT OF SYNC: {actual_override}")
                    all_in_sync = False
                else:
                    print(f"In sync: {actual_override}")
            else:
                print(f"MISSING: {actual_override}")
                all_in_sync = False

    return all_in_sync


def print_crd_fields(crd_content: str):
    """Print the CRD fields for informational purposes."""
    crd_json = json.loads(crd_content)

    for item in crd_json:
        if item[0] == "MaterializeSpec":
            fields = item[1]
            print("\nMaterializeSpec fields:")
            for field in fields:
                deprecated = " (DEPRECATED)" if field.get("deprecated", False) else ""
                required = " (required)" if field.get("required", False) else ""
                print(f"  - {field['name']}: {field['type']}{required}{deprecated}")
            break


def main():
    parser = argparse.ArgumentParser(
        description="Check that Terraform types are in sync with upstream schemas"
    )
    parser.add_argument(
        "--version",
        help="Materialize version tag (reads from source files if not specified)",
    )
    parser.add_argument(
        "--show-fields",
        action="store_true",
        help="Print CRD fields",
    )
    args = parser.parse_args()

    # Get version
    if args.version:
        version = args.version
    else:
        try:
            version = get_version_from_source()
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)

    print(f"Checking schema sync for Materialize version: {version}\n")

    # Check schemas are accessible
    crd_ok, helm_ok, crd_content, helm_content = check_schema_accessible(version)

    if not crd_ok or not helm_ok:
        print("\nError: One or more schemas are not accessible.", file=sys.stderr)
        print(
            f"This may indicate version {version} does not exist or paths have changed.",
            file=sys.stderr,
        )
        sys.exit(1)

    print()

    # Check types are in sync
    in_sync = check_types_in_sync(crd_content, helm_content)

    if args.show_fields:
        print_crd_fields(crd_content)

    print()
    if in_sync:
        print("All type definitions are in sync.")
        sys.exit(0)
    else:
        print("Error: Type definitions are out of sync.", file=sys.stderr)
        print(
            "Run 'uv run python scripts/generate_terraform_types.py' to update.",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
