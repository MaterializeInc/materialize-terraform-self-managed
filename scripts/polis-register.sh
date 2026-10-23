#!/bin/sh
#
# Registers (or re-reads) the Polis SAML connection and SCIM directory for an
# enterprise example deployment.
#
# Polis owns these two objects and their credentials only exist once it is
# running, so they cannot be Terraform resources. This script covers the Polis
# side; the remaining Okta admin-console steps are printed at the end (they are
# genuinely not scriptable).
#
# Credentials (the connection's client_secret, the SCIM token) go to a 0600
# file, not stdout, unless --print-secrets is given. The Polis admin API key
# reaches curl through a header file, never its argv.
#
# IDEMPOTENT: a connection or directory with the same name is re-read rather
# than duplicated, so this is also how you recover values you have lost. That
# matters -- Polis dedupes a repeated SAML connection POST but does NOT dedupe
# directories, so a second directory would get a different id and SCIM token and
# leave Okta pushing into whichever one happens to be configured.
#
# Requires: kubectl (pointed at the cluster), terraform, curl, python3, and on
# first registration the Okta SAML app's metadata XML:
#
#   OKTA_SAML_METADATA=~/Downloads/metadata.xml \
#     ./scripts/polis-register.sh gcp/examples/enterprise
#
set -eu
umask 077

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    echo "Usage: [OKTA_SAML_METADATA=<path>] $0 [--print-secrets] <example-dir>"
    echo ""
    echo "Arguments:"
    echo "  example-dir      path to the enterprise example, e.g. gcp/examples/enterprise"
    echo "  --print-secrets  also print client_secret and the SCIM token to stdout"
    echo ""
    echo "Environment variables:"
    echo "  OKTA_SAML_METADATA   path to the Okta SAML app metadata XML"
    echo "                       (required only on first registration)"
    echo "  ORY_NAMESPACE        namespace Ory runs in       (default: ory)"
    echo "  POLIS_TENANT         Polis tenant                (default: materialize)"
    echo "  POLIS_PRODUCT        Polis product               (default: materialize)"
    echo "  POLIS_OIDC_ID        saml_providers id           (default: polis)"
    echo "  POLIS_SECRETS_FILE   where credentials are written (0600)"
    echo "                       (default: <example-dir>/polis-credentials.txt)"
    exit 1
}

PRINT_SECRETS=0
if [ "${1:-}" = "--print-secrets" ]; then
    PRINT_SECRETS=1
    shift
fi
[ $# -eq 1 ] || usage
EXAMPLE_DIR="$1"
[ -d "$EXAMPLE_DIR" ] || {
    printf "%bno such directory: %s%b\n" "$RED" "$EXAMPLE_DIR" "$NC"
    exit 1
}

ORY_NAMESPACE="${ORY_NAMESPACE:-ory}"
TENANT="${POLIS_TENANT:-materialize}"
PRODUCT="${POLIS_PRODUCT:-materialize}"
SSO_NAME="${POLIS_SSO_NAME:-okta-saml}"
SCIM_NAME="${POLIS_SCIM_NAME:-okta-scim}"
OIDC_ID="${POLIS_OIDC_ID:-polis}"
SECRETS_FILE="${POLIS_SECRETS_FILE:-$EXAMPLE_DIR/polis-credentials.txt}"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf "%bmissing required tool: %s%b\n" "$RED" "$1" "$NC"
        exit 1
    }
}
need kubectl
need terraform
need curl
need python3

echo "==> reading hostnames from Terraform outputs"
ORY=$(terraform -chdir="$EXAMPLE_DIR" output -json ory)
POLIS=$(printf '%s' "$ORY" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("polis_external_url") or "")')
KRATOS=$(printf '%s' "$ORY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["kratos_external_url"])')
CONSOLE_FQDN=$(printf '%s' "$ORY" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("materialize_console_fqdn") or "")')
# Fall back to $MZ_CONSOLE_FQDN when the example's ory output predates the
# materialize_console_fqdn key. Only used for the SAML defaultRedirectUrl.
CONSOLE_FQDN="${CONSOLE_FQDN:-${MZ_CONSOLE_FQDN:-}}"

if [ -z "$POLIS" ]; then
    printf "%bPolis is not deployed (enable_polis = false in terraform.tfvars)%b\n" "$RED" "$NC"
    exit 1
fi
echo "    polis=$POLIS kratos=$KRATOS console=$CONSOLE_FQDN"

echo "==> reading the Polis admin API key from the cluster"
KEY=$(kubectl -n "$ORY_NAMESPACE" get secret polis-config -o jsonpath='{.data.API_KEYS}' | base64 -d)
if [ -z "$KEY" ]; then
    printf "%bempty admin API key -- is Polis running?%b\n" "$RED" "$NC"
    exit 1
fi

# Private scratch dir (umask 077) for the API key header and secrets that curl
# reads from files instead of its argv, which other local users can see.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
AUTH_HEADER="$WORK/auth-header"
printf 'Authorization: Api-Key %s\n' "$KEY" >"$AUTH_HEADER"

echo "==> checking Polis is reachable"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$POLIS/" || true)
if [ "$code" != "200" ]; then
    printf "%bPolis not reachable at %s (HTTP %s). Check DNS, the load balancer, and: kubectl -n %s get certificate polis-tls%b\n" \
        "$RED" "$POLIS" "$code" "$ORY_NAMESPACE" "$NC"
    exit 1
fi

# POST to the Polis admin API: check the HTTP status, unwrap the optional
# {"data": ...} envelope, and require <key> in the result, so a failed create
# never prints empty values into the Okta checklist below.
# Args: <key> <url> [curl form args...]
polis_post() {
    required_key="$1"
    post_url="$2"
    shift 2
    response_body=$(mktemp)
    status=$(curl -s -o "$response_body" -w '%{http_code}' -X POST "$post_url" \
        -H @"$AUTH_HEADER" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        "$@" || true)
    if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
        printf "%bPOST %s failed (HTTP %s):%b\n" "$RED" "$post_url" "$status" "$NC" >&2
        cat "$response_body" >&2
        rm -f "$response_body"
        return 1
    fi
    if ! python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    doc = json.loads(raw)
except ValueError:
    sys.exit("non-JSON response:\n" + raw)
if isinstance(doc, dict):
    doc = doc.get("data", doc)
if not isinstance(doc, dict) or not doc.get(sys.argv[1]):
    sys.exit("response is missing %r:\n%s" % (sys.argv[1], raw))
print(json.dumps(doc))
' "$required_key" < "$response_body"; then
        rm -f "$response_body"
        return 1
    fi
    rm -f "$response_body"
}

# ---------------------------------------------------------------------------
# SAML connection
# ---------------------------------------------------------------------------
# The redirectUrl is the Kratos SAML method callback (not oidc): Polis is wired
# as a Kratos SAML method, so Kratos completes the handshake at
# .../self-service/methods/saml/callback/<id>. defaultRedirectUrl is the console.
WANT_REDIRECT="$KRATOS/self-service/methods/saml/callback/$OIDC_ID"
WANT_DEFAULT="https://$CONSOLE_FQDN"

echo "==> SAML connection '$SSO_NAME'"
existing=$(curl -s "$POLIS/api/v1/sso?tenant=$TENANT&product=$PRODUCT" \
    -H @"$AUTH_HEADER")
sso=$(printf '%s' "$existing" | python3 -c '
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)
data = data if isinstance(data, list) else data.get("data", [])
for connection in data:
    if connection.get("name") == want:
        print(json.dumps(connection))
        break
' "$SSO_NAME")

if [ -n "$sso" ]; then
    # Reconcile rather than blindly re-read: a connection registered against an
    # older hostname or the pre-SAML oidc/callback path keeps that stale
    # redirectUrl forever otherwise, and Polis then rejects the login with
    # "Redirect URL is not allowed". Compare, and PATCH when it has drifted.
    drift=$(printf '%s' "$sso" | python3 -c '
import json, sys
c = json.load(sys.stdin)
want_r, want_d = sys.argv[1], sys.argv[2]
r = c.get("redirectUrl")
have_r = r[0] if isinstance(r, list) and r else (r if isinstance(r, str) else "")
have_d = c.get("defaultRedirectUrl") or ""
print("drift" if (have_r != want_r or have_d != want_d) else "ok")
print(have_r)
print(have_d)
' "$WANT_REDIRECT" "$WANT_DEFAULT")
    state=$(printf '%s\n' "$drift" | sed -n 1p)
    have_r=$(printf '%s\n' "$drift" | sed -n 2p)
    have_d=$(printf '%s\n' "$drift" | sed -n 3p)
    if [ "$state" = "ok" ]; then
        echo "    already registered, redirect URLs match"
    else
        printf "%b    redirect URLs have drifted:%b\n" "$RED" "$NC" >&2
        printf "      redirectUrl:        have %s\n                          want %s\n" "$have_r" "$WANT_REDIRECT" >&2
        printf "      defaultRedirectUrl: have %s\n                          want %s\n" "$have_d" "$WANT_DEFAULT" >&2
        if [ -n "${OKTA_SAML_METADATA:-}" ] && [ -s "${OKTA_SAML_METADATA:-}" ]; then
            cid=$(printf '%s' "$sso" | python3 -c 'import json,sys; print(json.load(sys.stdin)["clientID"])')
            printf '%s' "$sso" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["clientSecret"])' >"$WORK/client-secret"
            pcode=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "$POLIS/api/v1/sso" \
                -H @"$AUTH_HEADER" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                --data-urlencode "clientID=$cid" \
                --data-urlencode "clientSecret@$WORK/client-secret" \
                --data-urlencode "tenant=$TENANT" \
                --data-urlencode "product=$PRODUCT" \
                --data-urlencode "name=$SSO_NAME" \
                --data-urlencode "redirectUrl=$WANT_REDIRECT" \
                --data-urlencode "defaultRedirectUrl=$WANT_DEFAULT" \
                --data-urlencode "encodedRawMetadata=$(base64 < "$OKTA_SAML_METADATA" | tr -d '\n')" || true)
            if [ "$pcode" -ge 200 ] && [ "$pcode" -lt 300 ]; then
                printf "%b    reconciled the redirect URLs.%b\n" "$GREEN" "$NC"
                existing=$(curl -s "$POLIS/api/v1/sso?tenant=$TENANT&product=$PRODUCT" \
                    -H @"$AUTH_HEADER")
                sso=$(printf '%s' "$existing" | python3 -c '
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)
data = data if isinstance(data, list) else data.get("data", [])
for connection in data:
    if connection.get("name") == want:
        print(json.dumps(connection))
        break
' "$SSO_NAME")
            else
                printf "%b    PATCH to reconcile failed (HTTP %s); fix the connection manually.%b\n" "$RED" "$pcode" "$NC" >&2
            fi
        else
            printf "%b    set OKTA_SAML_METADATA=<path> and re-run to auto-fix, or update the connection in Polis manually.%b\n" "$RED" "$NC" >&2
        fi
    fi
else
    echo "    creating from the Okta app's SAML metadata"
    if [ -z "${OKTA_SAML_METADATA:-}" ]; then
        printf "%bset OKTA_SAML_METADATA to the metadata XML downloaded from Okta%b\n" "$RED" "$NC"
        exit 1
    fi
    if [ ! -s "$OKTA_SAML_METADATA" ]; then
        printf "%bmetadata file is missing or empty: %s%b\n" "$RED" "$OKTA_SAML_METADATA" "$NC"
        exit 1
    fi
    # encodedRawMetadata rather than metadataUrl: Okta gates the metadata URL
    # behind API auth on some org types, so Polis cannot fetch it itself. The
    # redirectUrl is the SAML method callback (Polis is a Kratos SAML method).
    sso=$(polis_post clientSecret "$POLIS/api/v1/sso" \
        --data-urlencode "tenant=$TENANT" \
        --data-urlencode "product=$PRODUCT" \
        --data-urlencode "name=$SSO_NAME" \
        --data-urlencode "redirectUrl=$WANT_REDIRECT" \
        --data-urlencode "defaultRedirectUrl=$WANT_DEFAULT" \
        --data-urlencode "encodedRawMetadata=$(base64 < "$OKTA_SAML_METADATA" | tr -d '\n')")
fi

# ---------------------------------------------------------------------------
# SCIM directory
# ---------------------------------------------------------------------------
echo "==> SCIM directory '$SCIM_NAME'"
existing=$(curl -s "$POLIS/api/v1/dsync?tenant=$TENANT&product=$PRODUCT" \
    -H @"$AUTH_HEADER")
dsync=$(printf '%s' "$existing" | python3 -c '
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)
data = data if isinstance(data, list) else data.get("data", [])
for directory in data:
    if directory.get("name") == want:
        print(json.dumps(directory))
        break
' "$SCIM_NAME")

if [ -n "$dsync" ]; then
    echo "    already registered -- re-reading (not duplicating)"
else
    echo "    creating"
    dsync=$(polis_post scim "$POLIS/api/v1/dsync" \
        --data-urlencode "tenant=$TENANT" \
        --data-urlencode "product=$PRODUCT" \
        --data-urlencode "name=$SCIM_NAME" \
        --data-urlencode "type=okta-scim-v2")
fi

# ---------------------------------------------------------------------------
# Output: what to do with the results
# ---------------------------------------------------------------------------
SSO_JSON="$sso" DSYNC_JSON="$dsync" POLIS="$POLIS" KRATOS="$KRATOS" \
    OIDC_ID="$OIDC_ID" EXAMPLE_DIR="$EXAMPLE_DIR" \
    SECRETS_FILE="$SECRETS_FILE" PRINT_SECRETS="$PRINT_SECRETS" python3 <<'PY'
import json, os

sso = json.loads(os.environ["SSO_JSON"])
dsync = json.loads(os.environ["DSYNC_JSON"])
scim = dsync.get("scim", {})
polis = os.environ["POLIS"]
kratos = os.environ["KRATOS"]
oidc_id = os.environ["OIDC_ID"]
example_dir = os.environ["EXAMPLE_DIR"]
secrets_file = os.environ["SECRETS_FILE"]
print_secrets = os.environ["PRINT_SECRETS"] == "1"
bar = "=" * 74


def providers_block(client_secret):
    return f"""saml_providers = [
  {{
    id            = "{oidc_id}"
    label         = "Okta"
    client_id     = "{sso.get('clientID','')}"
    client_secret = "{client_secret}"
    issuer_url    = "{polis}"
    auth_url      = "{polis}/api/oauth/authorize"
    token_url     = "{polis}/api/oauth/token"
    # Required: the email domains this IdP may sign in, e.g. ["example.com"].
    allowed_email_domains = ["example.com"]
    # Optional: keep only these groups, or only groups with this prefix.
    # allowed_groups = ["mz-admins"]
    # group_prefix   = "mz-"
  }},
]"""


secrets = f"""# Polis credentials for {polis}. Keep this file out of version control.

{providers_block(sso.get('clientSecret', ''))}

# SCIM directory (not wired to Kratos, see below)
scim_endpoint = "{scim.get('endpoint', '')}"
scim_token    = "{scim.get('secret', '')}"
"""
fd = os.open(secrets_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.fchmod(fd, 0o600)
with os.fdopen(fd, "w") as f:
    f.write(secrets)

print(f"""
{bar}
1. TERRAFORM -- add Polis as a SAML provider in terraform.tfvars
{bar}
{providers_block(sso.get('clientSecret', '') if print_secrets else '<client_secret from ' + secrets_file + '>')}

Also save the Okta SAML app's IdP metadata XML as:
  {example_dir}/idp-metadata.xml
main.tf reads it with file() and injects it as raw_idp_metadata_xml.

Re-apply; that renders the "Sign in with Okta" button on the Kratos login page.
Keep client_secret out of version control (it is a Terraform sensitive value).
""")

print(f"""{bar}
2. OKTA ADMIN CONSOLE -- not scriptable
{bar}
On the SAML application, General -> SAML Settings:
  Single sign-on URL          : {polis}/api/oauth/saml
  Audience URI (SP Entity ID) : https://saml.boxyhq.com
                                (or polis_saml_audience, if you set it)

SCIM is not wired to Kratos yet: users and groups Okta pushes land only in the
Polis directory, and deactivating a user in Okta does not end their Materialize
access. That ends when their Kratos session expires
(kratos_session_lifespan_seconds) or the token hook's max auth age passes, plus
the life of any access token already issued. Delete the Kratos identity to end
it sooner. The SCIM endpoint and token are in {secrets_file}.
""")

print(f"""{bar}
3. VERIFY
{bar}
# the SAML sign-in button present in Kratos
curl -s "{kratos}/self-service/login/browser" -H "Accept: application/json" \\
  | python3 -c 'import json,sys; [print(n["attributes"]["value"]) for n in json.load(sys.stdin)["ui"]["nodes"] if n.get("group")=="saml"]'

Credentials written to {secrets_file} (mode 0600).
""")

if print_secrets:
    print(bar)
    print(secrets)
PY

printf "%bDone.%b\n" "$GREEN" "$NC"
