#!/usr/bin/env bash
# Installs changie on a Linux x86_64 runner. Pinned by version and checksum,
# like the other CI tools.
set -euo pipefail

CHANGIE_VERSION="1.26.0"
CHANGIE_SHA256="eab168c8287a6e91912e1c02e5260911232d945bfd3c89d8a0e1ace6bb7b6161"

tmp=$(mktemp -d)
tarball="changie_${CHANGIE_VERSION}_linux_amd64.tar.gz"
curl -fsSL -o "$tmp/$tarball" \
  "https://github.com/miniscruff/changie/releases/download/v${CHANGIE_VERSION}/${tarball}"
echo "${CHANGIE_SHA256}  $tmp/$tarball" | sha256sum --check --strict
tar -xzf "$tmp/$tarball" -C "$tmp" changie
sudo install -m 755 "$tmp/changie" /usr/local/bin/changie
changie --version
