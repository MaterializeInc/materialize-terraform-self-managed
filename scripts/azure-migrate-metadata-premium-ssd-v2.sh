#!/bin/sh
#
# Moves the Materialize metadata database of an Azure deployment from Premium
# SSD to Premium SSD v2, and leaves Terraform tracking the result.
#
# Azure cannot change a Flexible Server's storage type in place, and in Terraform
# storage_type forces a replacement, which would destroy the metadata. Instead,
# this copies the server to a Premium SSD v2 read replica and swaps the two with a
# planned switchover, so Materialize keeps its data and is only briefly
# interrupted: the switchover itself (Azure quotes 1 to 3 minutes) and two
# environmentd restarts.
#
# A switchover needs a virtual endpoint, whose writer hostname follows the
# primary. The endpoint is temporary: in Terraform it requires a replica to exist,
# so keeping it would mean paying for a second server for good. Materialize is
# pointed at the writer hostname for the switchover, then at the new server
# directly, and the endpoint and the old server are deleted.
#
# Either edit the root first and run everything at once with `run`, or run the
# phases one at a time. Each phase is safe to re-run, and stops if the previous
# one has not finished. The runbook is scripts/azure-migrate-metadata-premium-ssd-v2.md.
#
#   ./scripts/azure-migrate-metadata-premium-ssd-v2.sh <terraform-root> run
#   ./scripts/azure-migrate-metadata-premium-ssd-v2.sh <terraform-root> <phase>
#
# Requires: az (logged in to the subscription), kubectl (pointed at the cluster),
# terraform, jq.
#
# RG, OLD_SERVER, NEW_SERVER, ENDPOINT, SUBNET, DNS_ZONE and the rest come from
# the state file the preflight phase writes, which load_state sources.
# shellcheck disable=SC2153
set -eu

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    cat >&2 <<EOF
Usage: $0 <terraform-root> <phase>

All at once (edit the root to point at the new server first, see the runbook):
  run           check the root edit, then every phase below, including the apply

Phases, in order:
  preflight     check the server can be migrated; records what later phases need
  replica       create the Premium SSD v2 read replica and the virtual endpoint
  point-writer  point Materialize at the endpoint's writer hostname (restarts environmentd)
  switchover    planned switchover: the replica becomes the primary
  point-direct  point Materialize at the new server's own hostname (restarts environmentd)
  cleanup       delete the virtual endpoint and the old server
  adopt         move Terraform state to the new server (after editing the root, see the
                runbook) and save a verified plan; apply it with
                terraform -chdir=<root> apply .ssdv2-adopt.tfplan
  finish        remove the generated files and check that the plan is clean
  rollback      before switchover only: point Materialize back at the old server and
                delete the replica and the endpoint

Environment variables:
  DATABASE_MODULE     address of the database module    (default: module.database)
  INSTANCE_NAMESPACE  namespace of the Materialize instance (default: materialize-environment)
  NEW_SERVER          name of the new server            (default: <current server>-v2)
  ENDPOINT_NAME       name of the virtual endpoint      (default: <current server>-ve)
  YES                 set to 1 to skip confirmation prompts
EOF
    exit 1
}

[ $# -eq 2 ] || usage
ROOT="$1"
PHASE="$2"
[ -d "$ROOT" ] || {
    printf "%bno such directory: %s%b\n" "$RED" "$ROOT" "$NC" >&2
    exit 1
}

DATABASE_MODULE="${DATABASE_MODULE:-module.database}"
INSTANCE_NAMESPACE="${INSTANCE_NAMESPACE:-materialize-environment}"
SERVER_ADDR="${DATABASE_MODULE}.azurerm_postgresql_flexible_server.postgres"
STATE_FILE="$ROOT/.ssdv2-migration.env"
IMPORTS_FILE="$ROOT/ssdv2-migration-imports.tf"
ADOPT_PLAN=".ssdv2-adopt.tfplan"

info() { printf "%b==>%b %s\n" "$GREEN" "$NC" "$*"; }
# The hint for running the next phase by hand; `run` runs it itself.
next() { [ -n "${IN_RUN:-}" ] || info "next: $*"; }
die() {
    printf "%berror:%b %s\n" "$RED" "$NC" "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

confirm() {
    [ "${YES:-}" = "1" ] && return 0
    printf "%s [y/N] " "$1"
    read -r answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || die "aborted"
}

tf() { terraform -chdir="$ROOT" "$@"; }

load_state() {
    [ -f "$STATE_FILE" ] || die "run the preflight phase first"
    # shellcheck disable=SC1090
    . "$STATE_FILE"
}

server_field() {
    # $1: server name, $2: JMESPath query
    az postgres flexible-server show -g "$RG" -n "$1" --query "$2" -o tsv
}

backend_secret() {
    kubectl get secret -n "$INSTANCE_NAMESPACE" -o name |
        grep -- '-materialize-backend$' | head -1 | sed 's|^secret/||'
}

metadata_url() {
    kubectl get secret -n "$INSTANCE_NAMESPACE" "$(backend_secret)" \
        -o jsonpath='{.data.metadata_backend_url}' | base64 -d
}

metadata_host() {
    # The last @ ends the credentials; the password itself may contain one.
    metadata_url | sed 's|^.*@\([^:/?@]*\)[:/?][^@]*$|\1|'
}

# Points Materialize's metadata URL at another host and restarts environmentd so
# it reconnects. The secret is managed by Terraform; the `adopt` phase makes
# Terraform agree with the final value.
repoint() {
    from="$(metadata_host)"
    to="$1"
    if [ "$from" = "$to" ]; then
        info "metadata URL already points at $to"
        return 0
    fi
    info "pointing the metadata URL at $to (was $from)"
    url="$(metadata_url | sed "s|@$from\([:/?]\)|@$to\1|")"
    encoded="$(printf '%s' "$url" | base64 | tr -d '\n')"
    kubectl patch secret -n "$INSTANCE_NAMESPACE" "$(backend_secret)" --type merge \
        -p "{\"data\":{\"metadata_backend_url\":\"$encoded\"}}" >/dev/null
    [ "$(metadata_host)" = "$to" ] || die "the metadata URL did not change"

    info "restarting environmentd"
    kubectl delete pod -n "$INSTANCE_NAMESPACE" -l materialize.cloud/app=environmentd --wait=true >/dev/null
    # The StatefulSet recreates the pod; wait for it to exist, then to be ready.
    i=0
    until kubectl get pod -n "$INSTANCE_NAMESPACE" -l materialize.cloud/app=environmentd -o name | grep -q .; do
        i=$((i + 1))
        [ "$i" -le 60 ] || die "environmentd pod was not recreated"
        sleep 5
    done
    kubectl wait pod -n "$INSTANCE_NAMESPACE" -l materialize.cloud/app=environmentd \
        --for=condition=Ready --timeout=600s >/dev/null
    info "environmentd is ready"
}

phase_preflight() {
    need az
    need kubectl
    need terraform
    need jq

    info "reading the metadata server from Terraform state ($SERVER_ADDR)"
    json="$(tf show -json | jq --arg a "$SERVER_ADDR" '
        [.values.root_module | .. | objects | select(.address? == $a)][0].values')"
    [ "$json" != "null" ] || die "$SERVER_ADDR is not in the state"
    id="$(printf '%s' "$json" | jq -r .id)"
    old="$(printf '%s' "$json" | jq -r .name)"
    rg="$(printf '%s' "$json" | jq -r .resource_group_name)"
    dbs="$(tf state list | grep -F "${DATABASE_MODULE}.azurerm_postgresql_flexible_server_database.databases[" |
        sed 's|.*\["\(.*\)"\]$|\1|' | tr '\n' ' ')"

    RG="$rg"
    tier="$(server_field "$old" sku.tier)"
    storage="$(server_field "$old" storage.type)"
    autogrow="$(server_field "$old" storage.autoGrow)"
    ha="$(server_field "$old" highAvailability.mode)"
    version="$(server_field "$old" version)"
    role="$(server_field "$old" replicationRole)"
    state="$(server_field "$old" state)"
    zone="$(server_field "$old" availabilityZone)"
    subnet="$(server_field "$old" network.delegatedSubnetResourceId)"
    dns_zone="$(server_field "$old" network.privateDnsZoneArmResourceId)"
    replicas="$(az postgres flexible-server replica list -g "$rg" -n "$old" --query 'length(@)' -o tsv)"

    [ "$state" = "Ready" ] || die "$old is $state, not Ready"
    [ "$storage" != "PremiumV2_LRS" ] || die "$old is already on Premium SSD v2"
    [ "$tier" != "Burstable" ] || die "Premium SSD v2 needs a General Purpose or Memory Optimized SKU; $old is Burstable"
    [ "$autogrow" != "Enabled" ] || die "Premium SSD v2 does not support storage autogrow; disable it on $old first"
    [ "$version" != "13" ] || die "Premium SSD v2 does not support PostgreSQL 13"
    [ "$ha" = "Disabled" ] || die "$old has high availability enabled ($ha); read replicas do not support it"
    [ "$role" = "Primary" ] || die "$old is a $role, not a primary"
    [ "$replicas" = "0" ] || [ -f "$STATE_FILE" ] || die "$old already has read replicas; remove them first"
    [ -n "$dbs" ] || die "no databases found under ${DATABASE_MODULE} in the state"
    [ -n "$subnet" ] || die "$old has no delegated subnet; only private-access servers are supported"

    new="${NEW_SERVER:-$old-v2}"
    endpoint="${ENDPOINT_NAME:-$old-ve}"

    # Flexible Server names are global, and Azure keeps a deleted server's name
    # reserved for a while, for example after a rollback. Catch that here, before
    # any downtime, rather than when the replica is created.
    if [ -z "$(az postgres flexible-server show -g "$rg" -n "$new" --query name -o tsv 2>/dev/null)" ]; then
        subscription="$(printf '%s' "$id" | cut -d/ -f3)"
        location="$(server_field "$old" location | tr -d ' ' | tr '[:upper:]' '[:lower:]')"
        available="$(az rest --method post \
            --url "https://management.azure.com/subscriptions/$subscription/providers/Microsoft.DBforPostgreSQL/locations/$location/checkNameAvailability?api-version=2024-08-01" \
            --body "{\"name\":\"$new\",\"type\":\"Microsoft.DBforPostgreSQL/flexibleServers\"}" \
            --query nameAvailable -o tsv)"
        [ "$available" = "true" ] || die "the server name $new is not available. A recently deleted server keeps its name for a while (for example after a rollback); set NEW_SERVER to another name, and use the same name for server_name in the root"
    fi
    current_host="$(metadata_host)"
    case "$current_host" in
    "$old".*) ;;
    *) die "Materialize's metadata URL points at $current_host, not $old" ;;
    esac

    cat >"$STATE_FILE" <<EOF
RG='$rg'
OLD_SERVER='$old'
OLD_ID='$id'
OLD_FQDN='$current_host'
NEW_SERVER='$new'
ENDPOINT='$endpoint'
ZONE='$zone'
SUBNET='$subnet'
DNS_ZONE='$dns_zone'
DATABASES='$dbs'
EOF
    info "OK: $old ($tier, $storage, zone ${zone:-none}) can be migrated"
    info "new server: $new, temporary virtual endpoint: $endpoint"
    info "databases to re-import: $dbs"
    info "recorded in $STATE_FILE"
    next "replica"
}

phase_replica() {
    load_state
    if [ -z "$(az postgres flexible-server show -g "$RG" -n "$NEW_SERVER" --query name -o tsv 2>/dev/null)" ]; then
        info "creating $NEW_SERVER, a Premium SSD v2 read replica of $OLD_SERVER (takes 10 to 20 minutes)"
        set -- --storage-type PremiumV2_LRS --subnet "$SUBNET" --private-dns-zone "$DNS_ZONE"
        [ -z "$ZONE" ] || set -- "$@" --zone "$ZONE"
        az postgres flexible-server replica create -g "$RG" -n "$NEW_SERVER" \
            --source-server "$OLD_ID" "$@" -o none
    else
        info "$NEW_SERVER already exists"
    fi
    [ "$(server_field "$NEW_SERVER" replicationRole)" = "AsyncReplica" ] ||
        die "$NEW_SERVER exists but is not a replica of $OLD_SERVER"

    if [ -z "$(az postgres flexible-server virtual-endpoint show -g "$RG" -s "$OLD_SERVER" -n "$ENDPOINT" --query name -o tsv 2>/dev/null)" ]; then
        info "creating the virtual endpoint $ENDPOINT"
        az postgres flexible-server virtual-endpoint create -g "$RG" -s "$OLD_SERVER" -n "$ENDPOINT" \
            --endpoint-type ReadWrite --members "$NEW_SERVER" -o none
    else
        info "virtual endpoint $ENDPOINT already exists"
    fi
    next "point-writer (restarts environmentd)"
}

phase_point_writer() {
    load_state
    repoint "$ENDPOINT.writer.postgres.database.azure.com"
    next "switchover"
}

phase_switchover() {
    load_state
    [ "$(metadata_host)" = "$ENDPOINT.writer.postgres.database.azure.com" ] ||
        die "Materialize is not on the writer hostname yet; run point-writer first"
    if [ "$(server_field "$NEW_SERVER" replicationRole)" = "Primary" ]; then
        info "$NEW_SERVER is already the primary"
    else
        confirm "Switch over to $NEW_SERVER? Materialize is interrupted for a few minutes."
        info "planned switchover to $NEW_SERVER"
        az postgres flexible-server replica promote -g "$RG" -n "$NEW_SERVER" \
            --promote-mode switchover --promote-option planned --yes -o none
    fi
    [ "$(server_field "$NEW_SERVER" replicationRole)" = "Primary" ] || die "$NEW_SERVER is not the primary"
    info "$NEW_SERVER is the primary; $OLD_SERVER is now $(server_field "$OLD_SERVER" replicationRole)"
    next "point-direct (restarts environmentd)"
}

phase_point_direct() {
    load_state
    [ "$(server_field "$NEW_SERVER" replicationRole)" = "Primary" ] || die "run switchover first"
    repoint "$NEW_SERVER.postgres.database.azure.com"
    next "cleanup"
}

phase_cleanup() {
    load_state
    case "$(metadata_host)" in
    "$NEW_SERVER".*) ;;
    *) die "Materialize is not on $NEW_SERVER yet; run point-direct first" ;;
    esac
    # The endpoint lives on whichever server is primary; after the switchover
    # that is the new one.
    for s in "$NEW_SERVER" "$OLD_SERVER"; do
        if [ -n "$(az postgres flexible-server virtual-endpoint show -g "$RG" -s "$s" -n "$ENDPOINT" --query name -o tsv 2>/dev/null)" ]; then
            info "deleting the virtual endpoint $ENDPOINT"
            az postgres flexible-server virtual-endpoint delete -g "$RG" -s "$s" -n "$ENDPOINT" --yes -o none
        fi
    done
    if [ -n "$(az postgres flexible-server show -g "$RG" -n "$OLD_SERVER" --query name -o tsv 2>/dev/null)" ]; then
        role="$(server_field "$OLD_SERVER" replicationRole)"
        [ "$role" != "Primary" ] || die "$OLD_SERVER is still a primary; not deleting it"
        confirm "Delete $OLD_SERVER (now a $role)? This cannot be undone."
        info "deleting $OLD_SERVER"
        az postgres flexible-server delete -g "$RG" -n "$OLD_SERVER" --yes -o none
    fi
    next "edit the root (see README), then run adopt"
}

phase_adopt() {
    load_state
    [ -z "$(az postgres flexible-server show -g "$RG" -n "$OLD_SERVER" --query name -o tsv 2>/dev/null)" ] ||
        die "$OLD_SERVER still exists; run cleanup first"
    new_id="$(server_field "$NEW_SERVER" id)"

    if tf state list | grep -qxF "$SERVER_ADDR"; then
        backup="$ROOT/terraform.tfstate.pre-ssdv2-$(date -u +%Y%m%dT%H%M%S)"
        tf state pull >"$backup"
        info "state backed up to $backup"
        for db in $DATABASES; do
            tf state rm "${DATABASE_MODULE}.azurerm_postgresql_flexible_server_database.databases[\"$db\"]" >/dev/null
        done
        tf state rm "$SERVER_ADDR" >/dev/null
        info "removed $OLD_SERVER from the state"
    fi

    {
        echo "# Generated by azure-migrate-metadata-premium-ssd-v2.sh. Remove after applying"
        echo "# (the finish phase does)."
        printf '\nimport {\n  to = %s\n  id = "%s"\n}\n' "$SERVER_ADDR" "$new_id"
        for db in $DATABASES; do
            printf '\nimport {\n  to = %s.azurerm_postgresql_flexible_server_database.databases["%s"]\n  id = "%s/databases/%s"\n}\n' \
                "$DATABASE_MODULE" "$db" "$new_id" "$db"
        done
    } >"$IMPORTS_FILE"
    info "wrote $IMPORTS_FILE"

    info "planning"
    tf plan -input=false -out="$ADOPT_PLAN" >/dev/null
    json="$(mktemp)"
    trap 'rm -f "$json"' EXIT
    tf show -json "$ADOPT_PLAN" >"$json"
    bad="$(jq -r --arg m "$DATABASE_MODULE." '.resource_changes[]
        | select(.address | startswith($m))
        | select(.change.actions | index("delete") or index("create"))
        | .address' "$json")"
    [ -z "$bad" ] || {
        rm -f "$ROOT/$ADOPT_PLAN"
        die "the plan would create or replace:
$bad
Check that the root sets server_name = \"$NEW_SERVER\" and storage_type = \"PremiumV2_LRS\" on the database module (see the runbook)."
    }
    imports="$(jq '[.resource_changes[] | select(.change.importing)] | length' "$json")"
    info "plan OK: $imports import(s), nothing created or replaced in $DATABASE_MODULE"
    info "saved as $ROOT/$ADOPT_PLAN"
    next "terraform -chdir=$ROOT apply $ADOPT_PLAN, then finish"
}

phase_finish() {
    load_state
    tf state list | grep -qxF "$SERVER_ADDR" || die "$SERVER_ADDR is not in the state; apply the adopt plan first"
    [ "$(tf state show -no-color "$SERVER_ADDR" | sed -n 's/^ *name *= *"\(.*\)"$/\1/p' | head -1)" = "$NEW_SERVER" ] ||
        die "$SERVER_ADDR in the state is not $NEW_SERVER"
    rm -f "$IMPORTS_FILE" "$ROOT/$ADOPT_PLAN"
    # Only the database module and Materialize's backend secret are the
    # migration's concern; drift elsewhere in the root is reported, not fatal.
    info "checking that the plan is clean for $DATABASE_MODULE and the backend secret"
    plan="$(mktemp)"
    tf plan -input=false -out="$plan" >/dev/null
    tf show -json "$plan" >"$plan.json"
    rm -f "$plan"
    ours="$(jq -r --arg m "$DATABASE_MODULE." '.resource_changes[]
        | select(.change.actions != ["no-op"] and .change.actions != ["read"])
        | select((.address | startswith($m)) or (.address | endswith("kubernetes_secret.materialize_backend")))
        | "\(.address) (\(.change.actions | join(",")))"' "$plan.json")"
    others="$(jq -r --arg m "$DATABASE_MODULE." '.resource_changes[]
        | select(.change.actions != ["no-op"] and .change.actions != ["read"])
        | select(((.address | startswith($m)) or (.address | endswith("kubernetes_secret.materialize_backend"))) | not)
        | "  \(.address) (\(.change.actions | join(",")))"' "$plan.json")"
    rm -f "$plan.json"
    [ -z "$ours" ] || die "the plan still changes what the migration manages:
$ours"
    [ -z "$others" ] || printf "%bnote:%b the plan has changes unrelated to the migration:\n%s\n" "$GREEN" "$NC" "$others"
    rm -f "$STATE_FILE"
    info "done: $NEW_SERVER (Premium SSD v2) is the metadata server, and Terraform tracks it"
}

# For `run`: before any downtime, check that the root already points at the new
# server. With the old server still in the state, the only change planned in the
# database module must be its server being replaced by NEW_SERVER on Premium SSD v2
# (plus its databases following it). Anything else means the edit is missing or
# wrong, and nothing has been touched yet.
check_root_edit() {
    load_state
    info "checking that the root points at $NEW_SERVER (plan only)"
    plan="$(mktemp)"
    tf plan -input=false -out="$plan" >/dev/null
    tf show -json "$plan" >"$plan.json"
    rm -f "$plan"
    server="$(jq -c --arg a "$SERVER_ADDR" '.resource_changes[] | select(.address == $a)
        | {actions: .change.actions, name: .change.after.name, storage: .change.after.storage_type}' "$plan.json")"
    other="$(jq -r --arg m "$DATABASE_MODULE." --arg a "$SERVER_ADDR" '.resource_changes[]
        | select(.address | startswith($m)) | select(.address != $a)
        | select(.change.actions != ["no-op"] and .change.actions != ["read"])
        | select((.address | contains("azurerm_postgresql_flexible_server_database.databases[")) | not)
        | .address' "$plan.json")"
    rm -f "$plan.json"
    expected="{\"actions\":[\"delete\",\"create\"],\"name\":\"$NEW_SERVER\",\"storage\":\"PremiumV2_LRS\"}"
    [ "$server" = "$expected" ] || die "the root does not point at the new server yet; on the database module set
  server_name = \"$NEW_SERVER\", storage_type = \"PremiumV2_LRS\", storage_iops and storage_throughput
(the plan for $SERVER_ADDR is: ${server:-no change})"
    [ -z "$other" ] || die "the root also changes, in $DATABASE_MODULE:
$other
Make only the edits in the runbook."
    info "the root is ready; don't run terraform apply until this finishes"
}

phase_run() {
    need az
    need kubectl
    need terraform
    need jq
    IN_RUN=1
    [ -f "$STATE_FILE" ] || phase_preflight
    check_root_edit
    phase_replica
    phase_point_writer
    phase_switchover
    phase_point_direct
    phase_cleanup
    phase_adopt
    info "applying the verified plan"
    tf apply -input=false "$ADOPT_PLAN"
    phase_finish
}

phase_rollback() {
    load_state
    if [ -n "$(az postgres flexible-server show -g "$RG" -n "$NEW_SERVER" --query name -o tsv 2>/dev/null)" ] &&
        [ "$(server_field "$NEW_SERVER" replicationRole)" = "Primary" ]; then
        die "$NEW_SERVER is already the primary; the switchover is done, so finish the migration instead"
    fi
    repoint "$OLD_FQDN"
    if [ -n "$(az postgres flexible-server virtual-endpoint show -g "$RG" -s "$OLD_SERVER" -n "$ENDPOINT" --query name -o tsv 2>/dev/null)" ]; then
        info "deleting the virtual endpoint $ENDPOINT"
        az postgres flexible-server virtual-endpoint delete -g "$RG" -s "$OLD_SERVER" -n "$ENDPOINT" --yes -o none
    fi
    if [ -n "$(az postgres flexible-server show -g "$RG" -n "$NEW_SERVER" --query name -o tsv 2>/dev/null)" ]; then
        confirm "Delete the replica $NEW_SERVER?"
        info "deleting $NEW_SERVER"
        az postgres flexible-server delete -g "$RG" -n "$NEW_SERVER" --yes -o none
    fi
    rm -f "$STATE_FILE"
    info "rolled back: Materialize is on $OLD_SERVER, and the replica and endpoint are gone"
}

case "$PHASE" in
run) phase_run ;;
preflight) phase_preflight ;;
replica) phase_replica ;;
point-writer) phase_point_writer ;;
switchover) phase_switchover ;;
point-direct) phase_point_direct ;;
cleanup) phase_cleanup ;;
adopt) phase_adopt ;;
finish) phase_finish ;;
rollback) phase_rollback ;;
*) usage ;;
esac
