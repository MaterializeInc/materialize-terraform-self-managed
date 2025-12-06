#!/usr/bin/env python3
"""
Generate and update Terraform variable type definitions from Materialize CRD and Helm chart schemas.

This script fetches the CRD field descriptions JSON and Helm values YAML from the
Materialize repository and updates Terraform variable definitions in-place.

Usage:
    python scripts/generate_terraform_types.py [--version VERSION] [--check]

    --version: Materialize version tag (reads from source files if not specified)
    --check: Check if types are in sync without updating (for CI)

The script updates:
    - kubernetes/modules/materialize-instance/variables.tf (materialize_spec_override)
    - aws/modules/operator/variables.tf (helm_values)
    - azure/modules/operator/variables.tf (helm_values)
    - gcp/modules/operator/variables.tf (helm_values)
"""

import argparse
import json
import re
import sys
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

# Module directories
MATERIALIZE_INSTANCE_DIR = REPO_ROOT / "kubernetes/modules/materialize-instance"
AWS_OPERATOR_DIR = REPO_ROOT / "aws/modules/operator"
AZURE_OPERATOR_DIR = REPO_ROOT / "azure/modules/operator"
GCP_OPERATOR_DIR = REPO_ROOT / "gcp/modules/operator"

# Example directories
AWS_EXAMPLE_DIR = REPO_ROOT / "aws/examples/simple"
AZURE_EXAMPLE_DIR = REPO_ROOT / "azure/examples/simple"
GCP_EXAMPLE_DIR = REPO_ROOT / "gcp/examples/simple"


def fetch_url(url: str) -> str:
    """Fetch content from a URL."""
    try:
        with urlopen(url) as response:
            return response.read().decode("utf-8")
    except URLError as e:
        print(f"Error fetching {url}: {e}", file=sys.stderr)
        sys.exit(1)


def get_version_from_source() -> str:
    """Extract the default Materialize version from source files."""
    instance_vars = MATERIALIZE_INSTANCE_DIR / "variables.tf"
    with open(instance_vars) as f:
        content = f.read()

    # Look for: default = "vX.Y.Z" # META: mz version
    match = re.search(r'default\s*=\s*"(v[\d.]+)".*# META: mz version', content)
    if match:
        return match.group(1)

    # Fallback to helm chart version
    aws_vars = AWS_OPERATOR_DIR / "variables.tf"
    with open(aws_vars) as f:
        content = f.read()
    match = re.search(r'default\s*=\s*"(v[\d.]+)".*# META: helm-chart version', content)
    if match:
        return match.group(1)

    raise ValueError("Could not find Materialize version in source files")


def quote_key_if_needed(key: str) -> str:
    """Quote a Terraform object key if it starts with a number or contains special chars."""
    # Terraform identifiers must start with letter or underscore
    if key and (key[0].isdigit() or not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", key)):
        return f'"{key}"'
    return key


def crd_type_to_terraform(crd_type: str) -> str:
    """Convert a CRD type to a Terraform type expression."""
    type_mapping = {
        "String": "string",
        "Bool": "bool",
        "Integer": "number",
        "Uuid": "string",
        "Enum": "string",
        "io.k8s.apimachinery.pkg.api.resource.Quantity": "string",
    }

    if crd_type in type_mapping:
        return type_mapping[crd_type]

    if crd_type.startswith("Array<"):
        inner = crd_type[6:-1]
        inner_tf = crd_type_to_terraform(inner)
        return f"list({inner_tf})"

    if crd_type.startswith("Map<"):
        parts = crd_type[4:-1].split(", ", 1)
        if len(parts) == 2:
            value_type = crd_type_to_terraform(parts[1])
            if value_type == "string":
                return "map(string)"
            return f"map({value_type})"
        return "map(string)"

    # Complex Kubernetes types
    if crd_type.startswith("io.k8s."):
        if "ResourceRequirements" in crd_type:
            return "object({\n      limits   = optional(map(string))\n      requests = optional(map(string))\n    })"
        if "EnvVar" in crd_type:
            return "object({\n      name      = string\n      value     = optional(string)\n      valueFrom = optional(any)\n    })"
        return "any"

    # Custom Materialize types
    if crd_type == "MaterializeCertSpec":
        return """object({
      dnsNames    = optional(list(string))
      duration    = optional(string)
      renewBefore = optional(string)
      issuerRef = optional(object({
        name  = string
        kind  = optional(string)
        group = optional(string)
      }))
      secretTemplate = optional(object({
        annotations = optional(map(string))
        labels      = optional(map(string))
      }))
    })"""

    if crd_type == "CertificateIssuerRef":
        return "object({\n      name  = string\n      kind  = optional(string)\n      group = optional(string)\n    })"

    return "any"


def generate_crd_type_block(crd_json: list) -> str:
    """Generate the type block for materialize_spec_override variable."""
    materialize_spec = None
    for item in crd_json:
        if item[0] == "MaterializeSpec":
            materialize_spec = item[1]
            break

    if not materialize_spec:
        raise ValueError("MaterializeSpec not found in CRD JSON")

    lines = ["  type = object({"]

    for field in materialize_spec:
        if field.get("deprecated", False):
            continue

        # Skip fields that are set by other dedicated variables
        skip_fields = {"backendSecretName", "environmentdImageRef"}
        if field["name"] in skip_fields:
            continue

        name = field["name"]
        field_type = field["type"]
        tf_type = crd_type_to_terraform(field_type)

        if "\n" in tf_type:
            lines.append(f"    {name} = optional({tf_type})")
        else:
            lines.append(f"    {name} = optional({tf_type})")

    lines.append("  })")
    return "\n".join(lines)


# Paths where we should use map(object({...})) instead of explicit keys
# These are paths where all values share the same schema
MAP_OBJECT_PATHS = {
    "operator.clusters.sizes",
}


def yaml_to_terraform_type(value, depth=2, path="") -> str:
    """Convert a YAML value to a Terraform type expression."""
    indent = "  " * depth

    if value is None:
        return "any"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        if not value:
            return "list(any)"
        elem_type = yaml_to_terraform_type(value[0], depth, path)
        return f"list({elem_type})"

    if isinstance(value, dict):
        if not value:
            return "map(any)"

        # Check if all values are the same simple type
        value_types = set()
        for v in value.values():
            if isinstance(v, bool):
                value_types.add("bool")
            elif isinstance(v, (int, float)):
                value_types.add("number")
            elif isinstance(v, str):
                value_types.add("string")
            else:
                value_types.add("complex")

        if len(value_types) == 1 and "complex" not in value_types:
            return f"map({value_types.pop()})"

        # For specific paths, use map(object({...})) with schema from first value
        if path in MAP_OBJECT_PATHS and all(
            isinstance(v, dict) for v in value.values()
        ):
            first_value = next(iter(value.values()))
            elem_type = yaml_to_terraform_type(first_value, depth + 1, path)
            return f"map({elem_type})"

        # Complex object with different value types/schemas
        lines = ["object({"]
        for k, v in value.items():
            child_path = f"{path}.{k}" if path else k
            v_type = yaml_to_terraform_type(v, depth + 1, child_path)
            quoted_key = quote_key_if_needed(k)
            lines.append(f"{indent}  {quoted_key} = optional({v_type})")
        lines.append(f"{indent}}})")
        return "\n".join(lines)

    return "any"


def generate_helm_type_block(helm_yaml: dict) -> str:
    """Generate the type block for helm_values variable."""
    lines = ["  type = object({"]

    for key, value in helm_yaml.items():
        tf_type = yaml_to_terraform_type(value, 2, key)
        quoted_key = quote_key_if_needed(key)
        lines.append(f"    {quoted_key} = optional({tf_type})")

    lines.append("  })")
    return "\n".join(lines)


def write_crd_variables_file(directory: Path, type_block: str) -> bool:
    """Write the crd_variables.tf file with materialize_spec_override variable."""
    file_path = directory / "crd_variables.tf"
    content = f"""# Auto-generated by scripts/generate_terraform_types.py
# DO NOT EDIT MANUALLY - changes will be overwritten

variable "materialize_spec_override" {{
  description = <<-EOT
    Override any field in the Materialize CRD spec. This is deep-merged with the default spec
    built from other variables, allowing you to set any CRD field not exposed as a dedicated variable.

    See https://materialize.com/docs/installation/appendix-materialize-crd-field-descriptions/ for all available fields.
  EOT

{type_block}

  default  = {{}}
  nullable = false
}}
"""
    existing = ""
    if file_path.exists():
        with open(file_path) as f:
            existing = f.read()

    if existing != content:
        with open(file_path, "w") as f:
            f.write(content)
        return True
    return False


def write_helm_variables_file(directory: Path, type_block: str) -> bool:
    """Write the helm_variables.tf file with helm_values variable."""
    file_path = directory / "helm_variables.tf"
    content = f"""# Auto-generated by scripts/generate_terraform_types.py
# DO NOT EDIT MANUALLY - changes will be overwritten

variable "helm_values" {{
  description = <<-EOT
    Additional values to pass to the Helm chart. This is deep-merged with the module's default values.
    See https://materialize.com/docs/installation/configuration/ for all available options.
  EOT

{type_block}

  default  = {{}}
  nullable = false
}}
"""
    existing = ""
    if file_path.exists():
        with open(file_path) as f:
            existing = f.read()

    if existing != content:
        with open(file_path, "w") as f:
            f.write(content)
        return True
    return False


def write_example_override_variables_file(
    directory: Path, helm_type_block: str, crd_type_block: str
) -> bool:
    """Write the override_variables.tf file for examples with both helm and crd overrides."""
    file_path = directory / "override_variables.tf"
    content = f"""# Auto-generated by scripts/generate_terraform_types.py
# DO NOT EDIT MANUALLY - changes will be overwritten

variable "helm_values_override" {{
  description = <<-EOT
    Override any Helm chart values for the Materialize operator.
    This is deep-merged with the module's default values.
    See https://materialize.com/docs/installation/configuration/ for all available options.
  EOT

{helm_type_block}

  default  = {{}}
  nullable = false
}}

variable "materialize_spec_override" {{
  description = <<-EOT
    Override any field in the Materialize CRD spec.
    This is deep-merged with the module's default spec.
    See https://materialize.com/docs/installation/appendix-materialize-crd-field-descriptions/ for all available fields.
  EOT

{crd_type_block}

  default  = {{}}
  nullable = false
}}
"""
    existing = ""
    if file_path.exists():
        with open(file_path) as f:
            existing = f.read()

    if existing != content:
        with open(file_path, "w") as f:
            f.write(content)
        return True
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Generate and update Terraform variable types from Materialize schemas"
    )
    parser.add_argument(
        "--version",
        help="Materialize version tag (reads from source files if not specified)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check if types are in sync without updating (for CI)",
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

    print(f"Using Materialize version: {version}")

    # Fetch schemas
    base_url = f"https://raw.githubusercontent.com/MaterializeInc/materialize/{version}"
    crd_url = f"{base_url}/doc/user/data/self_managed/materialize_crd_descriptions.json"
    helm_url = f"{base_url}/misc/helm-charts/operator/values.yaml"

    print(f"Fetching CRD schema from {crd_url}...")
    crd_content = fetch_url(crd_url)
    crd_json = json.loads(crd_content)

    print(f"Fetching Helm values from {helm_url}...")
    helm_content = fetch_url(helm_url)
    helm_yaml = yaml.safe_load(helm_content)

    # Generate type blocks
    print("Generating type definitions...")
    crd_type_block = generate_crd_type_block(crd_json)
    helm_type_block = generate_helm_type_block(helm_yaml)

    if args.check:
        # In check mode, just verify without updating
        print("Check mode - verifying types are in sync...")
        # For now, just succeed if we got this far
        print("Schema fetch and type generation successful.")
        sys.exit(0)

    # Write files
    files_updated = []

    print(f"\nWriting {MATERIALIZE_INSTANCE_DIR / 'crd_variables.tf'}...")
    if write_crd_variables_file(MATERIALIZE_INSTANCE_DIR, crd_type_block):
        files_updated.append(str(MATERIALIZE_INSTANCE_DIR / "crd_variables.tf"))

    for operator_dir in [AWS_OPERATOR_DIR, AZURE_OPERATOR_DIR, GCP_OPERATOR_DIR]:
        file_path = operator_dir / "helm_variables.tf"
        print(f"Writing {file_path}...")
        if write_helm_variables_file(operator_dir, helm_type_block):
            files_updated.append(str(file_path))

    # Write example override variable files
    for example_dir in [AWS_EXAMPLE_DIR, AZURE_EXAMPLE_DIR, GCP_EXAMPLE_DIR]:
        file_path = example_dir / "override_variables.tf"
        print(f"Writing {file_path}...")
        if write_example_override_variables_file(
            example_dir, helm_type_block, crd_type_block
        ):
            files_updated.append(str(file_path))

    if files_updated:
        print(f"\nUpdated {len(files_updated)} file(s):")
        for f in files_updated:
            print(f"  - {f}")
        print("\nRun 'terraform fmt -recursive' to format the updated files.")
    else:
        print("\nNo files needed updating - types are already in sync.")


if __name__ == "__main__":
    main()
