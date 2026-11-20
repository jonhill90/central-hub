#!/usr/bin/env bash
# TASK-0362: dev's SOPS file of the apps' secrets is deleted once teardown leaves 0 dev VMs, and the daily bundle holds
# prod only while dev is down (hosts/ansible/roles/agent_box/files/dev-secrets.sh, secrets-bundle.sh).
#   1. remove with 0 VMs in the state deletes openbao-kv.sops.json and keeps the seal key's copy, the AppRole IDs, the CA and
#      the snapshots; a second remove is a no-op that still passes.
#   2. remove with a VM in the state or an unreadable state keeps the file and fails; no state file counts as 0 VMs.
#   3. down is 0 only for no state file or a readable state with 0 VMs.
#   4. secrets-bundle.sh leaves dev out while dev is down, keeps it while a VM exists or the state is unreadable, and
#      always keeps prod. (sops and age-keygen are stand-ins that copy; the tar inside is read back.)
#   5. Every teardown path reaches the hook: the teardown stage runs TEARDOWN_HOOK after the destroy and not when the
#      destroy fails, the wrapper's env file sets it, and the role installs the script.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
role=$src/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok: $*"; }
bad() { echo "FAIL: $*"; fail=1; }

# dev-secrets.sh with its paths pointed into $t.
sed -e "s|^work=.*|work=$t/work|" -e "s|^keys=.*|keys=$t/keys|" "$role/files/dev-secrets.sh" > "$t/dev-secrets.sh"
chmod +x "$t/dev-secrets.sh"
mkdir -p "$t/work/state" "$t/keys/dev/openbao-snapshots" "$t/keys/prod" "$t/libexec"
state=$t/work/state/dev-vms.tfstate
vm='{"mode":"managed","type":"proxmox_virtual_environment_vm","instances":[{}]}'
reset() {
  for f in openbao-kv.sops.json openbao-seal.key.sops.json openbao-admin-role-id secrets-store-ca.crt openbao-snapshots/raft-1.snap; do echo x > "$t/keys/dev/$f"; done
}

reset; echo '{"resources":[]}' > "$state"
out=$("$t/dev-secrets.sh" remove)
[[ ! -e $t/keys/dev/openbao-kv.sops.json ]] && ok "0 VMs: the kv file is deleted ($out)" || bad "0 VMs: the kv file is still there"
keep=true; for f in openbao-seal.key.sops.json openbao-admin-role-id secrets-store-ca.crt openbao-snapshots/raft-1.snap; do [[ -e $t/keys/dev/$f ]] || keep=false; done
$keep && ok "the seal key's copy, the AppRole ID, the CA and the snapshots stay" || bad "something besides the kv file was deleted"
"$t/dev-secrets.sh" remove >/dev/null && ok "a second remove passes with nothing to delete" || bad "a second remove failed"

reset; echo "{\"resources\":[$vm]}" > "$state"
if "$t/dev-secrets.sh" remove 2>/dev/null; then bad "a VM in the state: remove passed"; else [[ -e $t/keys/dev/openbao-kv.sops.json ]] && ok "a VM in the state: kv file kept, remove fails" || bad "a VM in the state: the kv file was deleted"; fi
echo 'not json' > "$state"
if "$t/dev-secrets.sh" remove 2>/dev/null; then bad "unreadable state: remove passed"; else [[ -e $t/keys/dev/openbao-kv.sops.json ]] && ok "unreadable state: kv file kept" || bad "unreadable state: the kv file was deleted"; fi
rm -f "$state"
if "$t/dev-secrets.sh" remove >/dev/null 2>&1 && [[ ! -e $t/keys/dev/openbao-kv.sops.json ]]; then ok "no state file (dev never built, as rebuild.sh counts it): remove deletes the kv file and passes"; else bad "no state file: remove failed or kept the file"; fi
"$t/dev-secrets.sh" down && ok "down passes with no state file" || bad "down failed with no state file"
echo '{"resources":[]}' > "$state"; "$t/dev-secrets.sh" down && ok "down passes with 0 VMs" || bad "down failed with 0 VMs"
if "$t/dev-secrets.sh" bogus 2>/dev/null; then bad "an unknown action passed"; else ok "an unknown action is refused"; fi

# secrets-bundle.sh with stand-ins for sops and age-keygen.
cp "$t/dev-secrets.sh" "$t/libexec/dev-secrets.sh"
cat > "$t/libexec/age-keygen" <<'EOS'
#!/bin/bash
echo age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
EOS
cat > "$t/libexec/sops" <<'EOS'
#!/bin/bash
# encrypt and decrypt both copy the input (the last argument) to --output.
out=""; prev=""; for a in "$@"; do [[ $prev == --output ]] && out=$a; prev=$a; done
cp -- "${@: -1}" "$out"
EOS
chmod +x "$t/libexec/"*
mkdir -p "$t/keys/secrets-bundle"
printf 'BUNDLE_KEEP=3\n' > "$t/keys/secrets-bundle/settings.env"
echo x > "$t/keys/secrets-bundle/age-identity.txt"
echo prod-file > "$t/keys/prod/home.tfvars"
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^libexec=.*|libexec=$t/libexec|" "$role/files/secrets-bundle.sh" > "$t/secrets-bundle.sh"
grep -q "^keys=$t/keys" "$t/secrets-bundle.sh" && grep -q "^libexec=$t/libexec" "$t/secrets-bundle.sh" || { bad "the bundle script's paths were not replaced"; exit 1; }
listing() { tar -tf "$(ls -1 "$t/keys/secrets-bundle/bundles"/bundle-*.sops.json | tail -n 1)" | sort | tr '\n' ' '; }
bundle() { rm -rf "$t/keys/secrets-bundle/bundles"; HOME=$t bash "$t/secrets-bundle.sh" >/dev/null 2>"$t/err" || { cat "$t/err"; return 1; }; }

reset; echo '{"resources":[]}' > "$state"; bundle
l=$(listing); [[ $l == *prod/* && $l != *dev/* ]] && ok "dev down: the bundle holds prod only" || bad "dev down: bundle lists: $l"
echo "{\"resources\":[$vm]}" > "$state"; bundle
l=$(listing); [[ $l == *prod/* && $l == *dev/* ]] && ok "a dev VM exists: the bundle holds prod and dev" || bad "a VM exists: bundle lists: $l"
echo 'not json' > "$state"; bundle
l=$(listing); [[ $l == *dev/* ]] && ok "unreadable state: dev stays in the bundle" || bad "unreadable state: bundle lists: $l"

# Every teardown path reaches the hook.
sed -n '/^hook() {/p;/^run_stage() {/,/^}/p' "$src/hosts/rebuild-k8s.sh" > "$t/fn.sh"
run_teardown() { # <destroy rc> -> prints hook lines
  bash -c '
    ENV_NAME=dev; TFSTATE=/x; tofu_vars=(); repo=/r; INVENTORY=/i
    TEARDOWN_HOOK="echo HOOK-RAN"
    tofu_k8s() { if [ "$1" = destroy ]; then return '"$1"'; fi; return 0; }
    preflight_memory() { :; }
    . "$1"
    ( set -e; run_stage teardown )' _ "$t/fn.sh" 2>&1 || true
}
run_teardown 0 | grep -q HOOK-RAN && ok "the teardown stage runs TEARDOWN_HOOK after a passing destroy" || bad "the hook did not run after the destroy"
run_teardown 1 | grep -q HOOK-RAN && bad "the hook ran although the destroy failed" || ok "a failed destroy does not run the hook"
# A teardown with a target (prod) writes the state's moves first with a refresh-only apply, then destroys only the target; one
# without a target (dev) does not.
run_calls() { # <target or empty> -> prints the tofu_k8s calls, one per line
  bash -c '
    ENV_NAME=prod; TFSTATE=/x; tofu_vars=(-var-file=v); repo=/r; INVENTORY=/i
    TEARDOWN_TARGET="$2"
    tofu_k8s() { echo "tofu_k8s $*"; }
    preflight_memory() { :; }
    . "$1"
    ( set -e; run_stage teardown )' _ "$t/fn.sh" "$1" 2>&1 || true
}
c=$(run_calls proxmox_virtual_environment_vm.node | tr '\n' '|')
[[ $c == *"tofu_k8s init "*"|tofu_k8s apply -refresh-only -auto-approve -input=false -var-file=v|tofu_k8s destroy -auto-approve -input=false -target=proxmox_virtual_environment_vm.node -var-file=v|"* ]] \
  && ok "a teardown with a target writes the state's moves (refresh-only apply) before the targeted destroy" || bad "target teardown calls: $c"
c=$(run_calls "" | tr '\n' '|')
[[ $c != *"-refresh-only"* && $c == *"tofu_k8s destroy -auto-approve -input=false -var-file=v|"* ]] \
  && ok "a teardown without a target does no refresh-only apply" || bad "plain teardown calls: $c"
grep -q "^TEARDOWN_HOOK='\$libexec/dev-secrets.sh remove'" "$role/files/rebuild.sh" && ok "rebuild.sh's env file sets TEARDOWN_HOOK for every action that writes it" || bad "rebuild.sh does not set TEARDOWN_HOOK"
grep -q "src: dev-secrets.sh" "$role/tasks/secrets_bundle.yml" && ok "the role installs dev-secrets.sh" || bad "the role does not install dev-secrets.sh"
bash -n "$role/files/dev-secrets.sh" "$role/files/secrets-bundle.sh" "$role/files/rebuild.sh" "$src/hosts/rebuild-k8s.sh" && ok "bash -n passes on every changed script" || bad "bash -n failed"

exit $fail
