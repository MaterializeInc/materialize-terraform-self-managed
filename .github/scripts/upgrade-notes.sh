#!/usr/bin/env bash
# Manages the upgrade notes in changelog.d/YYYY-MM-DD-<slug>.md, see CONTRIBUTING.md.
#
#   upgrade-notes.sh check                      validate the pending notes
#   upgrade-notes.sh batch <version> [<latest>]  move the pending notes into UPGRADING.md
#   upgrade-notes.sh release-notes <version>    print the notes for a GitHub release
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_URL="https://github.com/MaterializeInc/materialize-terraform-self-managed"
NOTES_DIR="${REPO_ROOT}/changelog.d"
UPGRADING="${REPO_ROOT}/UPGRADING.md"
VERSION_HEADING='^## v[0-9]'
NOTE_NAME='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])-[a-z0-9]+(-[a-z0-9]+)*\.md$'

WORK_DIR=""
cleanup() {
  if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT

usage() {
  echo "usage: $0 check | batch <version> [<latest>] | release-notes <version>" >&2
  exit 2
}

require_version() {
  if [[ ! "${1:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must look like v1.2.3, got '${1:-}'" >&2
    exit 2
  fi
}

# Sortable form of a version, v1.2.3 -> 000010000200003.
version_key() {
  local major minor patch
  IFS=. read -r major minor patch <<< "${1#v}"
  printf '%05d%05d%05d\n' "$major" "$minor" "$patch"
}

# File names of the pending notes, oldest first.
pending_notes() {
  find "$NOTES_DIR" -mindepth 1 -maxdepth 1 -name '*.md' -exec basename {} \; | LC_ALL=C sort
}

# The PR that added a note, from the merge queue's squash commit title
# ("Title (#123)"). Empty when the note isn't committed yet.
note_pr() {
  git -C "$REPO_ROOT" log --diff-filter=A --format=%s -1 -- "changelog.d/$1" 2>/dev/null |
    sed -n 's/.*(#\([0-9][0-9]*\))$/\1/p'
}

check() {
  local status=0 name f
  while IFS= read -r name; do
    if [[ "$name" != .gitkeep && ! "$name" =~ $NOTE_NAME ]]; then
      echo "error: changelog.d/$name: name notes YYYY-MM-DD-<slug>.md, e.g. changelog.d/$(date +%Y-%m-%d)-azurerm-5.md" >&2
      status=1
    fi
  done < <(find "$NOTES_DIR" -mindepth 1 -maxdepth 1 -exec basename {} \;)
  [ "$status" -eq 0 ] || return 1

  while IFS= read -r name; do
    f="$NOTES_DIR/$name"
    if grep -q $'\r' "$f"; then
      echo "error: changelog.d/$name: use Unix (LF) line endings" >&2
      status=1
    fi
    if ! head -n 1 "$f" | grep -q '^### [^[:space:]]'; then
      echo "error: changelog.d/$name: the first line must be a '### Title' heading" >&2
      status=1
    fi
    if ! tail -n +2 "$f" | grep -q '[^[:space:]]'; then
      echo "error: changelog.d/$name: add what users need to do below the title" >&2
      status=1
    fi
    # '#' and '##' headings would sit level with the version headings. Lines
    # inside code blocks, like shell comments, don't count.
    if ! awk '/^[[:space:]]*(```|~~~)/ { code = !code } !code && /^##? / { exit 1 }' "$f"; then
      echo "error: changelog.d/$name: use '####' or deeper for headings below the title" >&2
      status=1
    fi
  done < <(pending_notes)
  return "$status"
}

batch() {
  local version=$1 latest=${2:-} top notes block tmp total start next at name pr f
  require_version "$version"
  [ -z "$latest" ] || require_version "$latest"
  check

  WORK_DIR=$(mktemp -d)
  block="$WORK_DIR/block.md"
  tmp="$WORK_DIR/UPGRADING.md"

  # A section newer than <latest> is unreleased. If the next version changed
  # since it was added, e.g. a PR with a bigger bump merged, rename it.
  if [ -n "$latest" ]; then
    top=$(grep -m 1 "$VERSION_HEADING" "$UPGRADING" | cut -c4- || true)
    if [ -n "$top" ] && [ "$top" != "$version" ] && [[ "$(version_key "$top")" > "$(version_key "$latest")" ]]; then
      awk -v from="## $top" -v to="## $version" '!done && $0 == from { $0 = to; done = 1 } 1' "$UPGRADING" > "$tmp"
      cat "$tmp" > "$UPGRADING"
      echo "Renamed the unreleased $top section to $version."
    fi
  fi

  notes=$(pending_notes)
  if [ -z "$notes" ]; then
    echo "No pending upgrade notes."
    return 0
  fi

  # Each title links to its PR when git knows it. $(...) drops trailing blank
  # lines, so every note ends with exactly one blank line.
  while IFS= read -r name; do
    f="$NOTES_DIR/$name"
    pr=$(note_pr "$name")
    if [ -n "$pr" ]; then
      printf '%s ([#%s](%s/pull/%s))\n' "$(head -n 1 "$f")" "$pr" "$REPO_URL" "$pr"
    else
      head -n 1 "$f"
    fi
    printf '%s\n\n' "$(tail -n +2 "$f")"
  done <<< "$notes" > "$block"

  # Insert before line $at: at the end of an existing $version section, or as
  # a new section above the newest release.
  total=$(($(wc -l < "$UPGRADING")))
  start=$(grep -n -F -x -m 1 "## $version" "$UPGRADING" | cut -d: -f1 || true)
  if [ -n "$start" ]; then
    next=$(tail -n "+$((start + 1))" "$UPGRADING" | grep -n -m 1 "$VERSION_HEADING" | cut -d: -f1 || true)
    if [ -n "$next" ]; then at=$((start + next)); else at=$((total + 1)); fi
  else
    at=$(grep -n -m 1 "$VERSION_HEADING" "$UPGRADING" | cut -d: -f1 || true)
    at=${at:-$((total + 1))}
    { printf '## %s\n\n' "$version"; cat "$block"; } > "$block.new"
    mv "$block.new" "$block"
  fi
  if [ "$at" -gt "$total" ]; then
    { echo; cat "$block"; } > "$block.new"
    mv "$block.new" "$block"
  fi

  { head -n "$((at - 1))" "$UPGRADING"; cat "$block"; tail -n "+$at" "$UPGRADING"; } > "$tmp"
  # Overwrite in place to keep the file's permissions.
  cat "$tmp" > "$UPGRADING"

  while IFS= read -r name; do
    rm -f -- "$NOTES_DIR/$name"
  done <<< "$notes"
  echo "Moved $(wc -l <<< "$notes" | tr -d ' ') upgrade note(s) into the $version section of UPGRADING.md."
}

# Empty when the version has no notes. Refuses while notes are pending, so a
# release can't skip them.
release_notes() {
  local version=$1 notes
  require_version "$version"
  if [ -n "$(pending_notes)" ]; then
    echo "error: the notes in changelog.d/ aren't in UPGRADING.md yet, batch them first (the Tag workflow does)" >&2
    exit 1
  fi
  notes=$(awk -v heading="## $version" '
    $0 == heading { found = 1; next }
    found && /^## v[0-9]/ { exit }
    found { print }
  ' "$UPGRADING")
  if [ -n "$notes" ]; then printf '## Upgrade notes\n%s\n' "$notes"; fi
}

case "${1:-}" in
  check) [ $# -eq 1 ] || usage; check ;;
  batch) [ $# -eq 2 ] || [ $# -eq 3 ] || usage; batch "$2" "${3:-}" ;;
  release-notes) [ $# -eq 2 ] || usage; release_notes "$2" ;;
  *) usage ;;
esac
