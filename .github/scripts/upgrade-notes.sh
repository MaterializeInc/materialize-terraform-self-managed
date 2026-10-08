#!/usr/bin/env bash
# Manages the upgrade notes in .upgrade-notes/<PR number>.md, see CONTRIBUTING.md.
#
#   upgrade-notes.sh check            validate the pending notes
#   upgrade-notes.sh batch <version>  move the pending notes into UPGRADING.md
#   upgrade-notes.sh show <version>   print a released version's notes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_URL="https://github.com/MaterializeInc/materialize-terraform-self-managed"
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

# PR numbers of the pending notes, oldest first.
pending_prs() {
  find "$NOTES_DIR" -mindepth 1 -maxdepth 1 -name '*.md' -exec basename {} .md \; | sort -n
}

check() {
  local status=0 name f
  while IFS= read -r name; do
    if [[ "$name" != .gitkeep && ! "$name" =~ ^[1-9][0-9]*\.md$ ]]; then
      echo "error: .upgrade-notes/$name: name upgrade notes after the PR, e.g. .upgrade-notes/123.md" >&2
      status=1
    fi
  done < <(find "$NOTES_DIR" -mindepth 1 -maxdepth 1 -exec basename {} \;)
  [ "$status" -eq 0 ] || return 1

  while IFS= read -r name; do
    f="$NOTES_DIR/$name.md"
    if grep -q $'\r' "$f"; then
      echo "error: .upgrade-notes/$name.md: use Unix (LF) line endings" >&2
      status=1
    fi
    if ! head -n 1 "$f" | grep -q '^### [^[:space:]]'; then
      echo "error: .upgrade-notes/$name.md: the first line must be a '### Title' heading" >&2
      status=1
    fi
    if ! tail -n +2 "$f" | grep -q '[^[:space:]]'; then
      echo "error: .upgrade-notes/$name.md: add what users need to do below the title" >&2
      status=1
    fi
    # A version heading inside a note would split the release section.
    if grep -q '^## v[0-9]' "$f"; then
      echo "error: .upgrade-notes/$name.md: must not contain a '## v...' heading" >&2
      status=1
    fi
  done < <(pending_prs)
  return "$status"
}

batch() {
  local version=$1 prs section tmp line pr f
  require_version "$version"
  check

  prs=$(pending_prs)
  if [ -z "$prs" ]; then
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

  # Each title links to its PR. $(...) drops trailing blank lines, so notes are
  # evenly spaced.
  {
    echo "## $version"
    while IFS= read -r pr; do
      f="$NOTES_DIR/$pr.md"
      echo
      printf '%s ([#%s](%s/pull/%s))\n' "$(head -n 1 "$f")" "$pr" "$REPO_URL" "$pr"
      printf '%s\n' "$(tail -n +2 "$f")"
    done <<< "$prs"
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

  while IFS= read -r pr; do
    rm -f -- "$NOTES_DIR/$pr.md"
  done <<< "$prs"
  echo "Moved $(wc -l <<< "$prs" | tr -d ' ') upgrade note(s) into the $version section of UPGRADING.md."
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
