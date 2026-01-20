#!/usr/bin/env python3
"""
Generate Terraform variable type definitions from Materialize CRD and Helm chart schemas.

This script fetches the CRD field descriptions and Helm parameter types from the
Materialize repository and generates Terraform variable definitions in native HCL format.

The version is read from the environmentd_version variable default in the source code.

Usage:
    python scripts/generate_terraform_types.py

The script generates:
    - kubernetes/modules/materialize-instance/crd_variables.gen.tf
    - kubernetes/modules/operator/helm_variables.gen.tf
    - aws/modules/operator/helm_variables.gen.tf
    - azure/modules/operator/helm_variables.gen.tf
    - gcp/modules/operator/helm_variables.gen.tf
    - aws/examples/simple/override_variables.gen.tf
    - azure/examples/simple/override_variables.gen.tf
    - gcp/examples/simple/override_variables.gen.tf

To check if types are in sync, use scripts/check_schema_sync.py instead.
"""

import json  # For parsing fetched JSON schemas
import subprocess
import sys
from pathlib import Path
from urllib.request import urlopen
from urllib.error import URLError

import hcl2
import yaml


SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent

# Module directories
MATERIALIZE_INSTANCE_DIR = REPO_ROOT / "kubernetes/modules/materialize-instance"

KUBERNETES_OPERATOR_DIR = REPO_ROOT / "kubernetes/modules/operator"
AWS_OPERATOR_DIR = REPO_ROOT / "aws/modules/operator"
AZURE_OPERATOR_DIR = REPO_ROOT / "azure/modules/operator"
GCP_OPERATOR_DIR = REPO_ROOT / "gcp/modules/operator"

# Example directories
AWS_EXAMPLE_DIR = REPO_ROOT / "aws/examples/simple"
AZURE_EXAMPLE_DIR = REPO_ROOT / "azure/examples/simple"
GCP_EXAMPLE_DIR = REPO_ROOT / "gcp/examples/simple"


def fetch_url(url: str, timeout: int = 30) -> str:
    """Fetch content from a URL."""
    try:
        with urlopen(url, timeout=timeout) as response:
            return response.read().decode("utf-8")
    except URLError as e:
        print(f"Error fetching {url}: {e}", file=sys.stderr)
        sys.exit(1)


def get_version_from_source() -> str:
    """Extract the default Materialize version from source files."""
    # Try to get version from environmentd_version variable
    instance_vars = MATERIALIZE_INSTANCE_DIR / "variables.tf"
    with open(instance_vars) as f:
        parsed = hcl2.load(f)

    for var in parsed.get("variable", []):
        if "environmentd_version" in var:
            default = var["environmentd_version"].get("default")
            if default:
                return default

    # Fallback to helm chart version from operator module
    aws_vars = AWS_OPERATOR_DIR / "variables.tf"
    with open(aws_vars) as f:
        parsed = hcl2.load(f)

    for var in parsed.get("variable", []):
        if "helm_chart_version" in var:
            default = var["helm_chart_version"].get("default")
            if default:
                return default

    raise ValueError("Could not find Materialize version in source files")


def build_crd_type_lookup(crd_json: list) -> dict:
    """Build a lookup dictionary from type name to fields."""
    return {item[0]: item[1] for item in crd_json}


def crd_type_to_terraform(
    crd_type: str, type_lookup: dict, visited: set[str] | None = None
) -> str:
    """Convert a CRD type to a Terraform type expression string."""
    if visited is None:
        visited = set()

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
        inner_tf = crd_type_to_terraform(inner, type_lookup, visited)
        return f"list({inner_tf})"

    if crd_type.startswith("Map<"):
        parts = crd_type[4:-1].split(", ", 1)
        if len(parts) == 2:
            value_type = crd_type_to_terraform(parts[1], type_lookup, visited)
            return f"map({value_type})"
        return "map(string)"

    # Check if this type is defined in the CRD JSON
    if crd_type in type_lookup:
        # Detect cycles to prevent infinite recursion
        if crd_type in visited:
            print(
                f"Warning: cycle detected for type '{crd_type}', using 'any'",
                file=sys.stderr,
            )
            return "any"
        visited.add(crd_type)
        return crd_fields_to_terraform_object(
            type_lookup[crd_type], type_lookup, visited
        )

    # Fallback for unknown types
    return "any"


def crd_fields_to_terraform_object(
    fields: list, type_lookup: dict, visited: set[str] | None = None
) -> str:
    """Convert a list of CRD fields to a Terraform object type expression."""
    if visited is None:
        visited = set()

    field_exprs = []
    for field in fields:
        if field.get("deprecated", False):
            continue
        name = field["name"]
        field_type = field["type"]
        tf_type = crd_type_to_terraform(field_type, type_lookup, visited)
        if field.get("required", False):
            field_exprs.append(f"{name} = {tf_type}")
        else:
            field_exprs.append(f"{name} = optional({tf_type})")
    return "object({" + ", ".join(field_exprs) + "})"


# Fields that are set by other dedicated variables and should be skipped
CRD_SKIP_FIELDS = {"backendSecretName"}


def generate_crd_type_expression(crd_json: list) -> str:
    """Generate the type expression string for materialize_spec_override variable."""
    type_lookup = build_crd_type_lookup(crd_json)

    materialize_spec = type_lookup.get("MaterializeSpec")
    if not materialize_spec:
        raise ValueError("MaterializeSpec not found in CRD JSON")

    fields = []
    for field in materialize_spec:
        if field.get("deprecated", False):
            continue

        if field["name"] in CRD_SKIP_FIELDS:
            continue

        name = field["name"]
        field_type = field["type"]
        tf_type = crd_type_to_terraform(field_type, type_lookup)
        fields.append(f"{name} = optional({tf_type})")

    return "object({" + ", ".join(fields) + "})"


# Paths where we should use map(object({...})) instead of explicit keys
# These are paths where all values share the same schema
MAP_OBJECT_PATHS = {
    "operator.clusters.sizes",
}

# Kubernetes type definitions for Helm chart parameters
# These map k8s/<type> annotations to Terraform type expressions
K8S_TYPES = {
    "k8s/nodeSelector": "map(string)",
    "k8s/tolerations": "list(object({key = optional(string), operator = optional(string), value = optional(string), effect = optional(string), tolerationSeconds = optional(number)}))",
    "k8s/affinity": "object({nodeAffinity = optional(object({requiredDuringSchedulingIgnoredDuringExecution = optional(any), preferredDuringSchedulingIgnoredDuringExecution = optional(any)})), podAffinity = optional(object({requiredDuringSchedulingIgnoredDuringExecution = optional(any), preferredDuringSchedulingIgnoredDuringExecution = optional(any)})), podAntiAffinity = optional(object({requiredDuringSchedulingIgnoredDuringExecution = optional(any), preferredDuringSchedulingIgnoredDuringExecution = optional(any)}))})",
}


def helm_type_to_terraform(helm_type: str) -> str:
    """Convert a Helm parameter type to a Terraform type."""
    # Check for Kubernetes types first
    if helm_type in K8S_TYPES:
        return K8S_TYPES[helm_type]

    type_mapping = {
        "string": "any",  # string in helm params often means complex YAML that's stringified
        "bool": "bool",
        "int": "number",
        "object": "object(any)",
        "list": "list(any)",
    }
    return type_mapping.get(helm_type, "any")


def build_helm_structure(helm_params: list) -> dict:
    """Build a nested structure from dotted key paths with their types."""
    root = {}
    for param in helm_params:
        key = param["key"]
        param_type = param["type"]

        parts = key.split(".")
        current = root

        # Navigate/create the nested structure
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            elif "_type" in current[part]:
                # This intermediate node was previously a leaf - convert to branch
                # Keep the type info but allow children
                pass
            current = current[part]

        # Set the leaf value with its type
        leaf_key = parts[-1]
        if leaf_key in current and isinstance(current[leaf_key], dict):
            # Node already exists with children, just add type info
            current[leaf_key]["_type"] = param_type
        else:
            current[leaf_key] = {"_type": param_type}

    return root


def structure_to_terraform_type(structure: dict, path: str) -> str:
    """Convert a nested structure to a Terraform type expression."""
    # Check if this is a leaf node (has _type and no other keys except _type)
    non_meta_keys = [k for k in structure.keys() if not k.startswith("_")]
    if "_type" in structure and not non_meta_keys:
        return helm_type_to_terraform(structure["_type"])

    # For specific paths, use map with schema from first child
    if path in MAP_OBJECT_PATHS:
        # Get the first child's structure to use as the map value type
        first_key = next((k for k in structure.keys() if not k.startswith("_")), None)
        if first_key is None:
            return "map(any)"
        first_child = structure[first_key]
        elem_type = structure_to_terraform_type(first_child, f"{path}.{first_key}")
        return f"map({elem_type})"

    # Build object type from children (skip meta keys like _type)
    fields = []
    for key, value in structure.items():
        if key.startswith("_"):
            continue
        child_path = f"{path}.{key}" if path else key
        child_type = structure_to_terraform_type(value, child_path)
        fields.append(f"{key} = optional({child_type})")

    return "object({" + ", ".join(fields) + "})"


def generate_helm_type_expression(helm_params: list) -> str:
    """Generate the type expression string for helm_values variable."""
    structure = build_helm_structure(helm_params)

    fields = []
    for key, value in structure.items():
        if key.startswith("_"):
            continue
        tf_type = structure_to_terraform_type(value, key)
        fields.append(f"{key} = optional({tf_type})")

    return "object({" + ", ".join(fields) + "})"


GENERATED_FILE_HEADER = f"""\
# Auto-generated by scripts/generate_terraform_types.py for {get_version_from_source()} - DO NOT EDIT MANUALLY
"""


def format_type_expr(type_expr: str, indent: int = 0) -> str:
    """Format a Terraform type expression with proper indentation."""
    indent_str = "  " * indent
    next_indent = "  " * (indent + 1)

    # Handle object types
    if type_expr.startswith("object({") and type_expr.endswith("})"):
        inner = type_expr[8:-2]
        if not inner:
            return "object({})"

        # Parse fields - need to handle nested structures
        fields = []
        current_field = ""
        depth = 0
        for char in inner:
            if char in "({[":
                depth += 1
                current_field += char
            elif char in ")}]":
                depth -= 1
                current_field += char
            elif char == "," and depth == 0:
                fields.append(current_field.strip())
                current_field = ""
            else:
                current_field += char
        if current_field.strip():
            fields.append(current_field.strip())

        formatted_fields = []
        for field in fields:
            # Split on first " = " to get name and type
            if " = " in field:
                name, field_type = field.split(" = ", 1)
                formatted_type = format_type_expr(field_type, indent + 1)
                formatted_fields.append(f"{next_indent}{name} = {formatted_type}")
            else:
                formatted_fields.append(f"{next_indent}{field}")

        return "object({\n" + "\n".join(formatted_fields) + f"\n{indent_str}}})"

    # Handle list types
    if type_expr.startswith("list(") and type_expr.endswith(")"):
        inner = type_expr[5:-1]
        formatted_inner = format_type_expr(inner, indent)
        return f"list({formatted_inner})"

    # Handle map types
    if type_expr.startswith("map(") and type_expr.endswith(")"):
        inner = type_expr[4:-1]
        formatted_inner = format_type_expr(inner, indent)
        return f"map({formatted_inner})"

    # Handle optional types
    if type_expr.startswith("optional(") and type_expr.endswith(")"):
        inner = type_expr[9:-1]
        formatted_inner = format_type_expr(inner, indent)
        return f"optional({formatted_inner})"

    # Primitive types or unknown - return as-is
    return type_expr


def build_variable_hcl(
    name: str, description: str, type_expr: str, default: str = "{}"
) -> str:
    """Build HCL for a single variable block with proper formatting."""
    # Escape for HCL: backslashes first, then quotes, then preserve \n as literal
    escaped_desc = (
        description.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    )

    formatted_type = format_type_expr(type_expr, indent=1)

    return f"""variable "{name}" {{
  description = "{escaped_desc}"
  type = {formatted_type}
  default  = {default}
  nullable = false
}}
"""


def run_terraform_fmt(file_path: Path) -> None:
    """Run terraform fmt on a file to ensure proper formatting."""
    try:
        subprocess.run(
            ["terraform", "fmt", str(file_path)],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"Warning: terraform fmt failed for {file_path}: {e.stderr}",
            file=sys.stderr,
        )
    except FileNotFoundError:
        print("Warning: terraform not found, skipping formatting", file=sys.stderr)


def write_variables_file(file_path: Path, hcl_content: str) -> None:
    """Write a Terraform variables file."""
    full_content = GENERATED_FILE_HEADER + "\n" + hcl_content

    with open(file_path, "w") as f:
        f.write(full_content)

    run_terraform_fmt(file_path)


def write_crd_variables_file(directory: Path, type_expr: str) -> None:
    """Write the crd_variables.gen.tf file with materialize_spec_override variable."""
    hcl_content = build_variable_hcl(
        name="materialize_spec_override",
        description=(
            "Override any field in the Materialize CRD spec. "
            "This is deep-merged with the default spec built from other variables, "
            "allowing you to set any CRD field not exposed as a dedicated variable.\n\n"
            "See https://materialize.com/docs/installation/appendix-materialize-crd-field-descriptions/ for all available fields."
        ),
        type_expr=type_expr,
    )
    write_variables_file(directory / "crd_variables.gen.tf", hcl_content)


def write_helm_variables_file(directory: Path, type_expr: str) -> None:
    """Write the helm_variables.gen.tf file with helm_values variable."""
    hcl_content = build_variable_hcl(
        name="helm_values",
        description=(
            "Additional values to pass to the Helm chart. "
            "This is deep-merged with the module's default values.\n\n"
            "See https://materialize.com/docs/installation/configuration/ for all available options."
        ),
        type_expr=type_expr,
    )
    write_variables_file(directory / "helm_variables.gen.tf", hcl_content)


def write_example_override_variables_file(
    directory: Path, helm_type_expr: str, crd_type_expr: str
) -> None:
    """Write the override_variables.gen.tf file for examples with both helm and crd overrides."""
    helm_var = build_variable_hcl(
        name="helm_values_override",
        description=(
            "Override any Helm chart values for the Materialize operator. "
            "This is deep-merged with the module's default values.\n\n"
            "See https://materialize.com/docs/installation/configuration/ for all available options."
        ),
        type_expr=helm_type_expr,
    )
    crd_var = build_variable_hcl(
        name="materialize_spec_override",
        description=(
            "Override any field in the Materialize CRD spec. "
            "This is deep-merged with the module's default spec.\n\n"
            "See https://materialize.com/docs/installation/appendix-materialize-crd-field-descriptions/ for all available fields."
        ),
        type_expr=crd_type_expr,
    )
    write_variables_file(
        directory / "override_variables.gen.tf", helm_var + "\n" + crd_var
    )


def main():
    # Get version from source files
    try:
        version = get_version_from_source()
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Using Materialize version: {version}")

    # Fetch schemas
    base_url = f"https://raw.githubusercontent.com/MaterializeInc/materialize/{version}"
    crd_url = f"{base_url}/doc/user/data/self_managed/materialize_crd_descriptions.json"
    helm_params_url = f"{base_url}/doc/user/data/self_managed/materialize_operator_chart_parameter.yml"

    print(f"Fetching CRD schema from {crd_url}...")
    crd_content = fetch_url(crd_url)
    crd_json = json.loads(crd_content)

    print(f"Fetching Helm parameter types from {helm_params_url}...")
    helm_params_content = fetch_url(helm_params_url)
    helm_params = yaml.safe_load(helm_params_content)

    # Generate type expressions
    print("Generating type definitions...")
    crd_type_expr = generate_crd_type_expression(crd_json)
    helm_type_expr = generate_helm_type_expression(helm_params)

    # Write files
    crd_file = MATERIALIZE_INSTANCE_DIR / "crd_variables.gen.tf"
    print(f"\nWriting {crd_file}...")
    write_crd_variables_file(MATERIALIZE_INSTANCE_DIR, crd_type_expr)

    for operator_dir in [
        KUBERNETES_OPERATOR_DIR,
        AWS_OPERATOR_DIR,
        AZURE_OPERATOR_DIR,
        GCP_OPERATOR_DIR,
    ]:
        file_path = operator_dir / "helm_variables.gen.tf"
        print(f"Writing {file_path}...")
        write_helm_variables_file(operator_dir, helm_type_expr)

    for example_dir in [AWS_EXAMPLE_DIR, AZURE_EXAMPLE_DIR, GCP_EXAMPLE_DIR]:
        file_path = example_dir / "override_variables.gen.tf"
        print(f"Writing {file_path}...")
        write_example_override_variables_file(
            example_dir, helm_type_expr, crd_type_expr
        )

    print("\nDone.")


if __name__ == "__main__":
    main()
