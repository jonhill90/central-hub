#!/usr/bin/env bash
# Narrow the agents' Azure account (agent-azure) to the backup roles, and prove it (agent pick 247).
# The steps of the runbook give-agents-access-to-azure.md, "Narrow agent-azure's rights", as one
# checked script, so nothing is typed by hand. Each subcommand logs what it runs and stops at the
# first result it did not expect.
#
#   narrow-agent-access.sh precheck              # read only: nothing in the subscription would be blocked
#   narrow-agent-access.sh plan                  # save the plan; prints its sha256 for the owner's card
#   narrow-agent-access.sh apply <sha256>        # apply that saved plan, only if its sha256 matches
#   narrow-agent-access.sh deny-check            # the two deny rules refuse, Owner still held
#   narrow-agent-access.sh remove-owner <c1-run> <opnsense-run>
#                                                # after both backups passed: remove agent-azure's Owner
#   narrow-agent-access.sh verify                # refusals, then one allowed grant, then no changes
#
# Run it on the machine that holds this root's state (backend.tf: a local file), with the Azure CLI
# signed in as agent-azure and the credentials file the Mac wrapper tofu-azure.sh reads. It needs
# azure.tfvars to set narrow_agent_access = true and agent_object_id, so every later plan keeps the
# narrowing. It never signs in, never prints a secret, and never gives Owner back: only the owner can.
# Written for bash 3.2 (macOS) and later.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cd "$here"

AZ=${NARROW_AZ:-az}
TOFU=${NARROW_TOFU:-tofu}
env_file=${NARROW_AZURE_ENV:-$HOME/.config/central-hub/azure.env}
work=${NARROW_STATE_DIR:-$HOME/.local/state/central-hub}
state=$work/azure-backup.tfstate
plan_file=$work/azure-backup-narrow.tfplan
marks=$work/narrow-agent-access
varfile=azure.tfvars

log() { printf '== %s\n' "$*"; }
stop() { printf 'STOP: %s\n' "$*" >&2; exit 4; }
usage() { sed -n '7,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

load_env() {
  [ -f "$env_file" ] || stop "no credentials file $env_file"
  # Only the credentials file counts, never values left in the calling shell.
  unset AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
  [ -n "${AZURE_CLIENT_ID:-}" ] || stop "AZURE_CLIENT_ID is not set in $env_file"
  [ -n "${AZURE_TENANT_ID:-}" ] || stop "AZURE_TENANT_ID is not set in $env_file"
  export ARM_TENANT_ID="$AZURE_TENANT_ID" ARM_CLIENT_ID="$AZURE_CLIENT_ID" ARM_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
}

# The CLI must be signed in as agent-azure itself, never as a person.
signed_in_as_agent() {
  local kind name
  kind=$("$AZ" account show --query user.type -o tsv)
  name=$("$AZ" account show --query user.name -o tsv)
  [ "$kind" = servicePrincipal ] && [ "$name" = "$AZURE_CLIENT_ID" ] || stop "the Azure CLI is not signed in as agent-azure"
  sub=$("$AZ" account show --query id -o tsv)
  export ARM_SUBSCRIPTION_ID="$sub"
}

tfvar_set() { grep -Eq "^[[:space:]]*$1[[:space:]]*=" "$varfile" 2>/dev/null; }

# agent_object_id in azure.tfvars must be agent-azure's own service principal, the account signed in.
agent_id_matches() {
  local want have
  want=$(sed -n 's/^[[:space:]]*agent_object_id[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$varfile" | head -n 1)
  [ -n "$want" ] || stop "azure.tfvars must set agent_object_id to a quoted ID"
  have=$("$AZ" ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv) || stop "could not read agent-azure's own service principal"
  [ "$want" = "$have" ] || stop "agent_object_id in azure.tfvars is not agent-azure's service principal object ID"
}

# Seconds since the time written in a mark file (0 if it has none).
age_of() { local t; t=$(cat "$1" 2>/dev/null || true); case $t in ''|*[!0-9]*) t=0 ;; esac; echo $(( $(date +%s) - t )); }
utc_at() { python3 -I -c 'import sys,time; print(time.strftime("%H:%M UTC", time.gmtime(int(sys.argv[1]))))' "$1"; }

# Learn: a new Deny policy assignment can take 30 minutes on average and 1 hour at worst to start
# denying (key-vault/general/azure-policy, "Feature limitations"); a role assignment change up to
# 10 minutes (role-based-access-control/troubleshooting).
policy_wait=3600
rbac_wait=600

tofu_init() { "$TOFU" init -input=false -backend-config="path=$state" >/dev/null; }

# One value from the applied state: python reads `tofu show -json`; $1 is a resource address, $2 an attribute.
state_value() {
  "$TOFU" show -json | python3 -I -c '
import json, sys
addr, attr = sys.argv[1], sys.argv[2]
def walk(m):
    for r in m.get("resources", []):
        yield r
    for c in m.get("child_modules", []):
        yield from walk(c)
for r in walk(json.load(sys.stdin).get("values", {}).get("root_module", {})):
    if r["address"] == addr:
        print(r["values"][attr]); break
else:
    sys.exit("not in state: " + addr)
' "$1" "$2"
}

sha256_of() { python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# Expect a refusal: the command must fail, and its message must contain $1.
expect_refused() {
  local want=$1; shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    return 1
  fi
  case $out in
    *"$want"*) log "refused as expected ($want)"; return 0 ;;
    *) stop "failed, but not with $want: $(printf '%s' "$out" | head -c 300)" ;;
  esac
}

expected_creates='["azurerm_role_assignment.agent_role_admin[0]", "azurerm_subscription_policy_assignment.deny_shared_key[0]", "azurerm_subscription_policy_assignment.deny_vault_access_policies[0]"]'

check_plan_file() {
  "$TOFU" show -json "$plan_file" | python3 -I -c '
import json, sys
want = json.loads(sys.argv[1])
d = json.load(sys.stdin)
changes = [r for r in d.get("resource_changes", []) if r["change"]["actions"] != ["no-op"]]
made = sorted(r["address"] for r in changes if r["change"]["actions"] == ["create"])
other = [r["address"] for r in changes if r["change"]["actions"] != ["create"]]
if other or made != sorted(want):
    sys.exit("the plan must only create %s; it creates %s and changes %s" % (want, made, other))
' "$expected_creates" || stop "the saved plan is not the narrowing alone"
}

cmd=${1:-}
[ -n "$cmd" ] || usage
mkdir -p "$marks"

case $cmd in
  precheck)
    load_env; signed_in_as_agent
    log "storage accounts that allow shared key access (must be none)"
    open_keys=$("$AZ" storage account list --query "length([?allowSharedKeyAccess!=\`false\`])" -o tsv) || stop "could not list the storage accounts"
    [ "$open_keys" = 0 ] || stop "$open_keys storage account(s) allow shared key access; the deny rule would block their updates"
    log "key vaults on access lists (must be none)"
    # `az keyvault list` without a group reads ARM's generic resource list, which carries no
    # properties, so each vault is read with `az keyvault show`.
    vault_ids=$("$AZ" keyvault list --query '[].id' -o tsv) || stop "could not list the key vaults"
    old_vaults=0
    for id in $vault_ids; do
      rbac=$("$AZ" keyvault show --ids "$id" --query properties.enableRbacAuthorization -o tsv) || stop "could not read key vault ${id##*/}"
      [ "$rbac" = true ] || { log "vault ${id##*/} has enableRbacAuthorization=${rbac:-unset}"; old_vaults=$((old_vaults + 1)); }
    done
    [ "$old_vaults" = 0 ] || stop "$old_vaults key vault(s) use access lists; the deny rule would block their updates"
    log "policy assignments now: $("$AZ" policy assignment list --query 'length(@)' -o tsv)"
    if tfvar_set keep_sas_signer; then stop "azure.tfvars still sets keep_sas_signer, which pick 247 removed"; fi
    tfvar_set narrow_agent_access || stop "azure.tfvars must set narrow_agent_access = true"
    tfvar_set agent_object_id || stop "azure.tfvars must set agent_object_id"
    agent_id_matches
    log "precheck passed"
    ;;

  plan)
    load_env; signed_in_as_agent
    if ! tfvar_set narrow_agent_access || ! tfvar_set agent_object_id; then stop "run precheck first"; fi
    agent_id_matches
    tofu_init
    "$TOFU" plan -input=false -no-color -var-file="$varfile" -out="$plan_file"
    check_plan_file
    log "saved plan $plan_file"
    log "sha256 $(sha256_of "$plan_file")  (this goes on the owner's card)"
    ;;

  apply)
    want=${2:-}
    [ -n "$want" ] || usage
    load_env; signed_in_as_agent
    [ -f "$plan_file" ] || stop "no saved plan; run plan first"
    have=$(sha256_of "$plan_file")
    [ "$have" = "$want" ] || stop "the saved plan's sha256 is $have, not the card's $want"
    tofu_init
    check_plan_file
    log "applying the saved plan $have"
    "$TOFU" apply -input=false -no-color "$plan_file"
    rm -f "$marks/deny-check.ok"
    date +%s > "$marks/applied.at"
    log "applied; run deny-check next (the deny rules can take up to an hour to start refusing)"
    ;;

  deny-check)
    load_env; signed_in_as_agent
    tofu_init
    rg=$(state_value azurerm_resource_group.backup name)
    location=$(state_value azurerm_resource_group.backup location)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # Templates only: validate checks them against the deny rules and creates nothing.
    cat > "$tmp/storage.json" <<JSON
{"\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#", "contentVersion": "1.0.0.0",
 "resources": [{"type": "Microsoft.Storage/storageAccounts", "apiVersion": "2023-05-01", "name": "narrowcheck$(date +%s)",
   "location": "$location", "sku": {"name": "Standard_LRS"}, "kind": "StorageV2",
   "properties": {"allowSharedKeyAccess": true}}]}
JSON
    cat > "$tmp/vault.json" <<JSON
{"\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#", "contentVersion": "1.0.0.0",
 "resources": [{"type": "Microsoft.KeyVault/vaults", "apiVersion": "2023-07-01", "name": "narrowcheck$(date +%s)",
   "location": "$location", "properties": {"tenantId": "$AZURE_TENANT_ID", "sku": {"family": "A", "name": "standard"},
   "enableRbacAuthorization": false, "accessPolicies": []}}]}
JSON
    for t in storage vault; do
      log "validate a new $t that the deny rules must refuse (creates nothing)"
      if ! expect_refused RequestDisallowedByPolicy "$AZ" deployment group validate -g "$rg" --template-file "$tmp/$t.json" -o none; then
        since=$(age_of "$marks/applied.at")
        if [ -f "$marks/applied.at" ] && [ "$since" -lt "$policy_wait" ]; then
          stop "the $t template passed validation $((since / 60)) minutes after apply; deny rules can take up to an hour, so wait until $(utc_at $(( $(date +%s) - since + policy_wait ))) and rerun deny-check (Owner still held)"
        fi
        stop "the $t template passed validation: the deny rules and the role-assigner are applied but unproven; stop before the backups, Owner still held"
      fi
    done
    touch "$marks/deny-check.ok"
    log "deny-check passed; run both backups (step 3), then remove-owner"
    ;;

  remove-owner)
    c1_run=${2:-}; offbox_run=${3:-}
    [ -n "$c1_run" ] && [ -n "$offbox_run" ] || stop "name the passed c1 backup run and OPNsense copy run"
    [ -f "$marks/deny-check.ok" ] || stop "deny-check has not passed since the last apply"
    load_env; signed_in_as_agent
    log "backups passed: c1 $c1_run, OPNsense copy $offbox_run"
    log "removing agent-azure's Owner on the subscription"
    "$AZ" role assignment delete --assignee "$AZURE_CLIENT_ID" --role Owner --scope "/subscriptions/$sub"
    left=$("$AZ" role assignment list --assignee "$AZURE_CLIENT_ID" --role Owner --scope "/subscriptions/$sub" --query 'length(@)' -o tsv)
    [ "$left" = 0 ] || stop "Owner is still assigned (a list can lag a delete by up to 10 minutes; list again before anything else)"
    date +%s > "$marks/owner-removed.ok"
    log "Owner removed; run verify after $(utc_at $(( $(date +%s) + rbac_wait ))), since role changes take up to 10 minutes"
    ;;

  verify)
    [ -f "$marks/owner-removed.ok" ] || stop "remove-owner has not run"
    since=$(age_of "$marks/owner-removed.ok")
    [ "$since" -ge "$rbac_wait" ] || stop "Owner was removed $((since / 60)) minutes ago; role changes take up to 10 minutes, so rerun verify after $(utc_at $(( $(date +%s) - since + rbac_wait )))"
    load_env; signed_in_as_agent
    tofu_init
    agent=$(state_value 'azurerm_role_assignment.agent_role_admin[0]' principal_id)
    rg_id=$(state_value azurerm_resource_group.backup id)
    vault_id=$(state_value azurerm_key_vault.opnsense id)
    container_id=$(state_value azurerm_storage_container.backup id)
    backup_sp=$(state_value azuread_service_principal.backup object_id)
    opnsense_sp=$(state_value azuread_service_principal.opnsense object_id)
    sub_scope=/subscriptions/$sub

    log "agent-azure gives itself Storage Blob Data Reader (must be refused)"
    if ! expect_refused AuthorizationFailed "$AZ" role assignment create --assignee-object-id "$agent" \
        --assignee-principal-type ServicePrincipal --role "Storage Blob Data Reader" --scope "$rg_id" -o none; then
      "$AZ" role assignment delete --assignee "$agent" --role "Storage Blob Data Reader" --scope "$rg_id" ||
        stop "agent-azure gave itself Storage Blob Data Reader on $rg_id and it could not be removed; ask the owner to remove it and give Owner back"
      stop "agent-azure could give itself a data role (removed again); ask the owner to give Owner back"
    fi
    log "the OPNsense app gets Key Vault Secrets User (must be refused)"
    if ! expect_refused AuthorizationFailed "$AZ" role assignment create --assignee-object-id "$opnsense_sp" \
        --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" --scope "$vault_id" -o none; then
      "$AZ" role assignment delete --assignee "$opnsense_sp" --role "Key Vault Secrets User" --scope "$vault_id" ||
        stop "the OPNsense app got Key Vault Secrets User and it could not be removed; ask the owner to remove it and give Owner back"
      stop "a secret-read role could be given (removed again); ask the owner to give Owner back"
    fi
    for rule in deny-storage-shared-key deny-vault-access-policies; do
      log "delete policy assignment $rule (must be refused)"
      expect_refused AuthorizationFailed "$AZ" policy assignment delete --name "$rule" --scope "$sub_scope" ||
        stop "policy assignment $rule could be deleted; ask the owner to give Owner back and re-apply"
      log "exempt the backup group from $rule (must be refused)"
      if ! expect_refused AuthorizationFailed "$AZ" policy exemption create --name "narrow-check-$rule" \
          --policy-assignment "$sub_scope/providers/Microsoft.Authorization/policyAssignments/$rule" \
          --exemption-category Waiver --scope "$rg_id" -o none; then
        "$AZ" policy exemption delete --name "narrow-check-$rule" --scope "$rg_id" ||
          stop "exemption narrow-check-$rule was made and could not be removed; ask the owner to remove it and give Owner back"
        stop "an exemption from $rule could be made (removed again); ask the owner to give Owner back"
      fi
    done

    # Positive control: an allowed grant that adds no reach. The backup app already holds Storage
    # Blob Data Contributor on its container (main.tf), so Reader there gives it nothing new.
    log "allowed grant: the backup app gets Storage Blob Data Reader on its own container, then removed"
    grant=$("$AZ" role assignment create --assignee-object-id "$backup_sp" --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Reader" --scope "$container_id" --query id -o tsv) ||
      stop "the narrowed account could not make an allowed grant; ask the owner to give Owner back"
    "$AZ" role assignment delete --ids "$grant" ||
      stop "the allowed grant $grant was made but could not be removed; remove it before anything else (it adds no reach)"
    log "plan must show no changes"
    rc=0
    "$TOFU" plan -input=false -no-color -detailed-exitcode -var-file="$varfile" >/dev/null || rc=$?
    [ "$rc" = 0 ] || stop "plan is not clean after the narrowing (exit $rc)"
    log "verify passed; run both backups again (step 6)"
    ;;

  *) usage ;;
esac
