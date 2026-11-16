#!/usr/bin/env bash
# hosts/terraform/azure/backup/narrow-agent-access.sh (pick 247) against stand-ins for az and tofu,
# which log every call and answer from the case's settings. Nothing reaches Azure.
#   1. precheck passes on a clean subscription, and stops on an account with shared keys, a vault on
#      access lists, a person's login, keep_sas_signer left in azure.tfvars, or no narrowing settings.
#   2. plan saves the plan and prints its sha256; a plan that changes anything else stops.
#   3. apply refuses a plan whose sha256 is not the card's and applies only the saved file.
#   4. deny-check passes only when both templates are refused by policy, and stops as "unproven".
#   5. remove-owner needs deny-check and both backup runs, then removes Owner only.
#   6. verify passes on refusals plus one allowed grant and a clean plan; a refusal that does not
#      happen is undone and stops.
# Usage: .github/hosts-check/tests/test_narrow_agent_access.sh   (needs python3)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/root" "$work/bin" "$work/state"
cp "$root/hosts/terraform/azure/backup/narrow-agent-access.sh" "$work/root/"
script=$work/root/narrow-agent-access.sh
calls=$work/calls.log
cfg=$work/cfg

cat > "$work/azure.env" <<'ENV'
AZURE_TENANT_ID=22222222-2222-2222-2222-222222222222
AZURE_CLIENT_ID=33333333-3333-3333-3333-333333333333
AZURE_CLIENT_SECRET=not-a-secret
ENV

# The az stand-in: settings are files in $cfg, named after what they change.
cat > "$work/bin/az" <<'AZ'
#!/usr/bin/env bash
cfg=$STUB_CFG
printf 'az %s\n' "$*" >> "$STUB_CALLS"
get() { cat "$cfg/$1" 2>/dev/null || printf '%s' "$2"; }
case "$*" in
  "account show --query user.type -o tsv") get user_type servicePrincipal; echo ;;
  "account show --query user.name -o tsv") get user_name 33333333-3333-3333-3333-333333333333; echo ;;
  "account show --query id -o tsv") echo 00000000-0000-0000-0000-000000000000 ;;
  "storage account list"*) get open_keys 0; echo ;;
  "keyvault list"*) get old_vaults 0; echo ;;
  "policy assignment list"*) echo 1 ;;
  "deployment group validate"*)
    [ -f "$cfg/validate_passes" ] && exit 0
    echo "ERROR: (RequestDisallowedByPolicy) Resource was disallowed by policy." >&2; exit 1 ;;
  "role assignment delete"*) exit 0 ;;
  "role assignment list"*) get owner_left 0; echo ;;
  "role assignment create"*"Storage Blob Data Reader"*"blobServices"*)
    echo /subscriptions/0/providers/Microsoft.Authorization/roleAssignments/grant1 ;;
  "role assignment create"*"Storage Blob Data Reader"*)
    [ -f "$cfg/self_grant_works" ] && exit 0
    echo "ERROR: (AuthorizationFailed) does not have authorization" >&2; exit 1 ;;
  "role assignment create"*)
    echo "ERROR: (AuthorizationFailed) does not have authorization" >&2; exit 1 ;;
  "policy assignment delete"*|"policy exemption create"*)
    echo "ERROR: (AuthorizationFailed) does not have authorization" >&2; exit 1 ;;
  *) echo "az stand-in: unexpected call: $*" >&2; exit 9 ;;
esac
AZ

# The tofu stand-in: a plan file, a plan JSON and a state JSON from $cfg.
cat > "$work/bin/tofu" <<'TOFU'
#!/usr/bin/env bash
cfg=$STUB_CFG
printf 'tofu %s\n' "$*" >> "$STUB_CALLS"
case "$1" in
  init) exit 0 ;;
  plan)
    for a in "$@"; do case $a in -out=*) printf 'plan-bytes' > "${a#-out=}" ;; esac; done
    for a in "$@"; do [ "$a" = -detailed-exitcode ] && exit "$(cat "$cfg/plan_rc" 2>/dev/null || echo 0)"; done
    exit 0 ;;
  show)
    if [ $# -eq 3 ]; then cat "$cfg/plan.json"; else cat "$cfg/state.json"; fi ;;
  apply) exit 0 ;;
  *) echo "tofu stand-in: unexpected: $*" >&2; exit 9 ;;
esac
TOFU
chmod +x "$work/bin/az" "$work/bin/tofu"

reset() {
  rm -rf "$cfg" "$work/state"; mkdir -p "$cfg" "$work/state"; : > "$calls"
  printf 'narrow_agent_access = true\nagent_object_id = "99999999-9999-9999-9999-999999999999"\n' > "$work/root/azure.tfvars"
  cat > "$cfg/plan.json" <<'JSON'
{"resource_changes": [
 {"address": "azurerm_role_assignment.agent_role_admin[0]", "change": {"actions": ["create"]}},
 {"address": "azurerm_subscription_policy_assignment.deny_shared_key[0]", "change": {"actions": ["create"]}},
 {"address": "azurerm_subscription_policy_assignment.deny_vault_access_policies[0]", "change": {"actions": ["create"]}},
 {"address": "azurerm_storage_account.backup", "change": {"actions": ["no-op"]}}]}
JSON
  cat > "$cfg/state.json" <<'JSON'
{"values": {"root_module": {"resources": [
 {"address": "azurerm_resource_group.backup", "values": {"name": "rg-c1-backup", "location": "eastus2", "id": "/subscriptions/0/resourceGroups/rg-c1-backup"}},
 {"address": "azurerm_role_assignment.agent_role_admin[0]", "values": {"principal_id": "99999999-9999-9999-9999-999999999999"}},
 {"address": "azurerm_key_vault.opnsense", "values": {"id": "/subscriptions/0/resourceGroups/rg-c1-backup/providers/Microsoft.KeyVault/vaults/kv"}},
 {"address": "azurerm_storage_container.backup", "values": {"id": "/subscriptions/0/resourceGroups/rg-c1-backup/providers/Microsoft.Storage/storageAccounts/sa/blobServices/default/containers/c1-backup"}},
 {"address": "azuread_service_principal.backup", "values": {"object_id": "55555555-5555-5555-5555-555555555555"}},
 {"address": "azuread_service_principal.opnsense", "values": {"object_id": "66666666-6666-6666-6666-666666666666"}}]}}}
JSON
}

run() {
  STUB_CFG=$cfg STUB_CALLS=$calls NARROW_AZ=$work/bin/az NARROW_TOFU=$work/bin/tofu \
    NARROW_AZURE_ENV=$work/azure.env NARROW_STATE_DIR=$work/state bash "$script" "$@" > "$work/out" 2>&1
}
ok() { run "$@" || { cat "$work/out"; echo "FAIL: expected '$*' to pass" >&2; exit 1; }; }
stops() {
  local want=$1; shift
  if run "$@"; then cat "$work/out"; echo "FAIL: expected '$*' to stop" >&2; exit 1; fi
  grep -q "$want" "$work/out" || { cat "$work/out"; echo "FAIL: '$*' stopped without '$want'" >&2; exit 1; }
}
called() { grep -q -- "$1" "$calls" || { cat "$calls"; echo "FAIL: no call matching '$1'" >&2; exit 1; }; }
not_called() { if grep -q -- "$1" "$calls"; then cat "$calls"; echo "FAIL: unexpected call '$1'" >&2; exit 1; fi; }

# 1. precheck
reset; ok precheck
reset; echo 1 > "$cfg/open_keys"; stops "allow shared key access" precheck
reset; echo 1 > "$cfg/old_vaults"; stops "use access lists" precheck
reset; echo user > "$cfg/user_type"; stops "not signed in as agent-azure" precheck
reset; echo 'keep_sas_signer = true' >> "$work/root/azure.tfvars"; stops "keep_sas_signer" precheck
reset; : > "$work/root/azure.tfvars"; stops "narrow_agent_access" precheck
echo "ok 1 precheck"

# 2. plan
reset; ok plan
grep -q "sha256 $(printf 'plan-bytes' | sha256sum | cut -d' ' -f1)" "$work/out" || { cat "$work/out"; echo "FAIL: plan did not print the saved plan's sha256" >&2; exit 1; }
sed -i 's/"no-op"/"delete"/' "$cfg/plan.json"; stops "not the narrowing alone" plan
echo "ok 2 plan"

# 3. apply
sha=$(printf 'plan-bytes' | sha256sum | cut -d' ' -f1)
reset; ok plan; : > "$calls"; stops "not the card's" apply 0000; not_called "tofu apply"
ok apply "$sha"; called "tofu apply -input=false -no-color $work/state/azure-backup-narrow.tfplan"
echo "ok 3 apply"

# 4. deny-check
reset; touch "$cfg/validate_passes"; stops "unproven" deny-check
[ ! -f "$work/state/narrow-agent-access/deny-check.ok" ] || { echo "FAIL: deny-check marked a pass" >&2; exit 1; }
reset; ok deny-check; called "deployment group validate -g rg-c1-backup"
echo "ok 4 deny-check"

# 5. remove-owner
reset; stops "deny-check has not passed" remove-owner run-c1 run-opn; not_called "role assignment delete"
reset; ok deny-check; stops "name the passed" remove-owner run-c1
ok remove-owner run-c1 run-opn
called "role assignment delete --assignee 33333333-3333-3333-3333-333333333333 --role Owner --scope /subscriptions/00000000-0000-0000-0000-000000000000"
reset; ok deny-check; echo 1 > "$cfg/owner_left"; stops "still assigned" remove-owner run-c1 run-opn
echo "ok 5 remove-owner"

# 6. verify
reset; stops "remove-owner has not run" verify
reset; ok deny-check; ok remove-owner a b; : > "$calls"; ok verify
called "policy assignment delete --name deny-storage-shared-key"
called "policy exemption create --name narrow-check-deny-vault-access-policies"
called "role assignment delete --ids /subscriptions/0/providers/Microsoft.Authorization/roleAssignments/grant1"
called "tofu plan -input=false -no-color -detailed-exitcode"
reset; ok deny-check; ok remove-owner a b; touch "$cfg/self_grant_works"; : > "$calls"
stops "could give itself a data role" verify
called "role assignment delete --assignee 99999999-9999-9999-9999-999999999999 --role Storage Blob Data Reader"
reset; ok deny-check; ok remove-owner a b; echo 2 > "$cfg/plan_rc"; stops "plan is not clean" verify
echo "ok 6 verify"
echo "narrow-agent-access: all cases pass"
