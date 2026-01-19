"""
Tests for generate_terraform_types.py

These tests use fixture files to validate that the Terraform type generation
produces correct output for representative CRD and Helm schemas.
"""

import json
import subprocess
import tempfile
from pathlib import Path

import pytest
import yaml

from scripts.generate_terraform_types import (
    build_variable_hcl,
    generate_crd_type_expression,
    generate_helm_type_expression,
)

FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def crd_schema():
    """Load the CRD schema fixture."""
    with open(FIXTURES_DIR / "crd_schema.json") as f:
        return json.load(f)


@pytest.fixture
def helm_params():
    """Load the Helm parameters fixture."""
    with open(FIXTURES_DIR / "helm_params.yml") as f:
        return yaml.safe_load(f)


@pytest.fixture
def expected_crd_vars():
    """Load the expected CRD variables output."""
    with open(FIXTURES_DIR / "expected_crd_vars.tf") as f:
        return f.read()


@pytest.fixture
def expected_helm_vars():
    """Load the expected Helm variables output."""
    with open(FIXTURES_DIR / "expected_helm_vars.tf") as f:
        return f.read()


def _strip_header(content: str) -> str:
    """Strip the auto-generated header from Terraform content."""
    lines = content.split("\n")
    start = 0
    for i, line in enumerate(lines):
        if line.strip() and not line.startswith("#"):
            start = i
            break
    return "\n".join(lines[start:])


def _format_with_terraform(content: str) -> str:
    """Format Terraform content using terraform fmt for consistent comparison."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".tf", delete=False) as f:
        f.write(content)
        f.flush()
        temp_path = Path(f.name)

    try:
        subprocess.run(
            ["terraform", "fmt", str(temp_path)],
            check=True,
            capture_output=True,
        )
        return temp_path.read_text()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return content
    finally:
        temp_path.unlink(missing_ok=True)


def test_crd_variable_generation(crd_schema, expected_crd_vars):
    """Test that CRD schema fixture produces expected Terraform output."""
    type_expr = generate_crd_type_expression(crd_schema)
    generated = build_variable_hcl(
        name="materialize_spec_override",
        description=(
            "Override any field in the Materialize CRD spec. "
            "This is deep-merged with the default spec built from other variables, "
            "allowing you to set any CRD field not exposed as a dedicated variable.\n\n"
            "See https://materialize.com/docs/installation/appendix-materialize-crd-field-descriptions/ for all available fields."
        ),
        type_expr=type_expr,
    )

    generated_formatted = _format_with_terraform(generated)
    expected_formatted = _format_with_terraform(_strip_header(expected_crd_vars))

    assert generated_formatted == expected_formatted


def test_helm_variable_generation(helm_params, expected_helm_vars):
    """Test that Helm params fixture produces expected Terraform output."""
    type_expr = generate_helm_type_expression(helm_params)
    generated = build_variable_hcl(
        name="helm_values",
        description=(
            "Additional values to pass to the Helm chart. "
            "This is deep-merged with the module's default values.\n\n"
            "See https://materialize.com/docs/installation/configuration/ for all available options."
        ),
        type_expr=type_expr,
    )

    generated_formatted = _format_with_terraform(generated)
    expected_formatted = _format_with_terraform(_strip_header(expected_helm_vars))

    assert generated_formatted == expected_formatted
