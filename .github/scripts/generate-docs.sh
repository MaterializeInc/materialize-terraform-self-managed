#!/usr/bin/env bash
set -euo pipefail

# Determine repo root path relative to this script
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Path to terraform-docs config
TFDOCS_CONFIG="${REPO_ROOT}/.terraform-docs.yml"

# Check terraform-docs is installed
if ! command -v terraform-docs &> /dev/null; then
  echo "❌ terraform-docs is not installed. Install it from https://terraform-docs.io/"
  exit 1
fi

echo "📘 Generating module documentation using config at: $TFDOCS_CONFIG"
echo

# Dynamically find all directories that contain a 'modules' subdirectory
echo "🔍 Discovering module directories..."
MODULE_DIRS=()
while IFS= read -r -d '' modules_dir; do
  MODULE_DIRS+=("$modules_dir")
done < <(find "$REPO_ROOT" -maxdepth 2 -type d -name "modules" -print0)

if [[ ${#MODULE_DIRS[@]} -eq 0 ]]; then
  echo "⚠️  No 'modules' directories found in the repository"
  exit 1
fi

echo "📁 Found module directories:"
for dir in "${MODULE_DIRS[@]}"; do
  echo "   ${dir#$REPO_ROOT/}"
done
echo

# Loop through each discovered module directory
for MODULE_BASE_DIR in "${MODULE_DIRS[@]}"; do
  echo "🔍 Searching for modules in: ${MODULE_BASE_DIR#$REPO_ROOT/}"

  # Find all modules with variables.tf in this directory
  MODULES_FOUND=false
  find "$MODULE_BASE_DIR" -type f -name "variables.tf" | while read -r tf_file; do
    MODULE_DIR="$(dirname "$tf_file")"
    echo "📄 Updating docs for module: ${MODULE_DIR#$REPO_ROOT/}"
    MODULES_FOUND=true

    terraform-docs --config "$TFDOCS_CONFIG" "$MODULE_DIR" > "$MODULE_DIR/README.md"
  done

  # Check if any modules were found in this directory
  if ! find "$MODULE_BASE_DIR" -type f -name "variables.tf" -print -quit | grep -q .; then
    echo "   ℹ️  No modules with variables.tf found in ${MODULE_BASE_DIR#$REPO_ROOT/}"
  fi
  echo
done

echo "✅ Documentation generated for all modules."
