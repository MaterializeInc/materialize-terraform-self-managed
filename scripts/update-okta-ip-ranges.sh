#!/bin/sh
#
# Writes Okta's published egress IP ranges for a given cell to
# <example-dir>/okta-scim-source-ranges.json, so Terraform can apply them as
# loadBalancerSourceRanges on the Polis LoadBalancer.
#
# Why: Okta pushes SCIM provisioning server-to-server from its cloud (no browser
# in the loop), so the Polis LB can stay public but firewalled to Okta's egress
# ranges plus your own internal ranges. See ory_polis_source_ranges in the
# example and the README "Locking down the Polis endpoint" section.
#
# Okta publishes ranges per cell; find yours in the Okta admin console
# (Settings). Pass it explicitly: there is no default, so you never silently
# allowlist a different tenant's cell.
#
#   ./scripts/update-okta-ip-ranges.sh gcp/examples/enterprise <your-okta-cell>
#
set -eu

OKTA_RANGES_URL="https://s3.amazonaws.com/okta-ip-ranges/ip_ranges.json"

usage() {
    echo "Usage: $0 <example-dir> <okta-cell>" >&2
    echo "  example-dir  path to the enterprise example, e.g. gcp/examples/enterprise" >&2
    echo "  okta-cell    your Okta cell (find it in the Okta admin console, Settings)" >&2
    exit 1
}

[ $# -ge 2 ] || usage
DIR="$1"
CELL="$2"

[ -d "$DIR" ] || {
    echo "no such directory: $DIR" >&2
    exit 1
}
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

OUT="$DIR/okta-scim-source-ranges.json"

# Stage through a temp file so a failed fetch or an unknown cell never clobbers
# the existing allowlist. #!/bin/sh has no pipefail, so a `curl | jq > "$OUT"`
# pipeline would truncate $OUT up front and still exit 0 when the fetch fails
# (S3 blip, proxy, 403), leaving a 0-byte file that breaks the next
# `terraform plan` on jsondecode(""). Writing $OUT only after both steps
# succeed avoids that; set -e aborts on the curl or jq failure first.
TMP="$(mktemp)"
trap 'rm -f "$TMP" "$TMP.out"' EXIT
curl -sSf "$OKTA_RANGES_URL" > "$TMP"
jq --arg cell "$CELL" '
    .[$cell].ip_ranges
    | if . == null then error("cell \($cell) not found in ip_ranges.json") else . end
    | sort
' "$TMP" > "$TMP.out"
mv "$TMP.out" "$OUT"

echo "Wrote $(jq length "$OUT") ranges for $CELL to $OUT"
