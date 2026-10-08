#!/usr/bin/env bash
# Manages the upgrade notes in .upgrade-notes/, see CONTRIBUTING.md.
#
#   upgrade-notes.sh check            validate the pending notes
#   upgrade-notes.sh batch <version>  move the pending notes into UPGRADING.md
#   upgrade-notes.sh show <version>   print a released version's notes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTES_DIR="${REPO_ROOT}/.upgrade-notes"
UPGRADING="${REPO_ROOT}/UPGRADING.md"

WORK_DIR=""
cleanup() {
  if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT

usage() {
  echo "usage: $0 check | batch <version> | show <version>" >&2
  exit 2
}

require_version() {
  if [[ ! "${1:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must look like v1.2.3, got '${1:-}'" >&2
    exit 2
  fi
}

# Pending notes in a stable order.
pending_notes() {
  LC_ALL=C find "$NOTES_DIR" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort
}

check() {
  local status=0 f
  while IFS= read -r f; do
    case "$(basename "$f")" in
      .gitkeep | *.md) ;;
      *)
        echo "error: ${f#"$REPO_ROOT"/}: upgrade notes must be .md files" >&2
        status=1
        ;;
    esac
  done < <(find "$NOTES_DIR" -mindepth 1 -maxdepth 1)

  while IFS= read -r f; do
    if ! head -n 1 "$f" | grep -q '^### [^[:space:]]'; then
      echo "error: ${f#"$REPO_ROOT"/}: the first line must be a '### Title' heading" >&2
      status=1
    fi
    # A version heading inside a note would split the release section.
    if grep -q '^## v[0-9]' "$f"; then
      echo "error: ${f#"$REPO_ROOT"/}: must not contain a '## v...' heading" >&2
      status=1
    fi
  done < <(pending_notes)
  return "$status"
}

batch() {
  local version=$1 notes section tmp line f
  require_version "$version"
  check

  notes=$(pending_notes)
  if [ -z "$notes" ]; then
    echo "No pending upgrade notes."
    return 0
  fi
  if grep -qx "## $version" "$UPGRADING"; then
    echo "error: UPGRADING.md already has a $version section" >&2
    exit 1
  fi

  WORK_DIR=$(mktemp -d)
  section="$WORK_DIR/section.md"
  tmp="$WORK_DIR/UPGRADING.md"

  {
    echo "## $version"
    while IFS= read -r f; do
      echo
      # $(...) drops trailing blank lines, so notes are evenly spaced.
      printf '%s\n' "$(cat "$f")"
    done <<< "$notes"
    echo
  } > "$section"

  # The newest release goes on top, right after the header.
  line=$(grep -n -m 1 '^## v' "$UPGRADING" | cut -d: -f1 || true)
  if [ -n "$line" ]; then
    { head -n "$((line - 1))" "$UPGRADING"; cat "$section"; tail -n "+$line" "$UPGRADING"; } > "$tmp"
  else
    { cat "$UPGRADING"; echo; cat "$section"; } > "$tmp"
  fi
  # Overwrite in place to keep the file's permissions.
  cat "$tmp" > "$UPGRADING"

  while IFS= read -r f; do
    rm -f -- "$f"
  done <<< "$notes"
  echo "Moved $(wc -l <<< "$notes" | tr -d ' ') upgrade note(s) into the $version section of UPGRADING.md."
}

show() {
  local version=$1
  require_version "$version"
  awk -v heading="## $version" '
    $0 == heading { found = 1; next }
    found && /^## v/ { exit }
    found { print }
  ' "$UPGRADING"
}

case "${1:-}" in
  check) [ $# -eq 1 ] || usage; check ;;
  batch) [ $# -eq 2 ] || usage; batch "$2" ;;
  show) [ $# -eq 2 ] || usage; show "$2" ;;
  *) usage ;;
esac
