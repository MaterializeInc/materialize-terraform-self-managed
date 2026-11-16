#!/bin/sh
# Reads the cloudflared tunnel token from Secret Manager into an env file for
# the cloudflared unit. The secret version to read is in the instance metadata
# attribute `tunnel-token-secret`; the VM's service account authorizes the read.
set -eu

md=http://metadata.google.internal/computeMetadata/v1
out=/run/cloudflared/env

secret=$(curl -sf --retry 10 --retry-connrefused --retry-delay 3 \
  -H 'Metadata-Flavor: Google' "$md/instance/attributes/tunnel-token-secret")

access_token=$(curl -sf --retry 10 --retry-connrefused --retry-delay 3 \
  -H 'Metadata-Flavor: Google' "$md/instance/service-accounts/default/token" |
  tr -d ' \n' | sed -E 's/.*"access_token":"([^"]+)".*/\1/')

data=$(curl -sf --retry 10 --retry-connrefused --retry-delay 3 \
  -H "Authorization: Bearer $access_token" \
  "https://secretmanager.googleapis.com/v1/$secret:access" |
  tr -d ' \n' | sed -E 's/.*"data":"([^"]+)".*/\1/')

umask 077
mkdir -p "$(dirname "$out")"
printf 'TUNNEL_TOKEN=%s\n' "$(printf '%s' "$data" | base64 -d)" > "$out"
