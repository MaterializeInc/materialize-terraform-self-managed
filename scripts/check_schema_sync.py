#!/usr/bin/env python3
"""
Check that generated Terraform type definitions are in sync with upstream schemas.

Runs the generation script and checks if any files changed.

Exit codes:
    0: All files in sync
    1: Files out of sync or uncommitted changes exist
"""

import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent

GENERATED_FILES = [
    "kubernetes/modules/materialize-instance/crd_variables.gen.tf",
    "kubernetes/modules/operator/helm_variables.gen.tf",
    "aws/modules/operator/helm_variables.gen.tf",
    "azure/modules/operator/helm_variables.gen.tf",
    "gcp/modules/operator/helm_variables.gen.tf",
    "aws/examples/simple/override_variables.gen.tf",
    "azure/examples/simple/override_variables.gen.tf",
    "gcp/examples/simple/override_variables.gen.tf",
]


def main():
    # Check for uncommitted changes to generated files
    result = subprocess.run(
        ["git", "diff", "--name-only", "--"] + GENERATED_FILES,
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    if result.stdout.strip():
        print("Error: Uncommitted changes to generated files:", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        sys.exit(1)

    # Run generation
    print("Running generate_terraform_types.py...")
    result = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "generate_terraform_types.py")],
        cwd=REPO_ROOT,
    )
    if result.returncode != 0:
        sys.exit(result.returncode)

    # Check for diff
    result = subprocess.run(
        ["git", "diff", "--name-only", "--"] + GENERATED_FILES,
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    if result.stdout.strip():
        print("\nError: Generated files are out of sync:", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(
            "\nRun 'uv run python scripts/generate_terraform_types.py' to update.",
            file=sys.stderr,
        )
        sys.exit(1)

    print("\nAll generated files are in sync.")


if __name__ == "__main__":
    main()
