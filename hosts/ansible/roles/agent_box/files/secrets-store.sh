#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store.sh: build and set up the lab's secrets store, OpenBao,
# on dev (docs/runbooks/set-up-the-secrets-store.md, proposed D-0038). It runs as user `keys` through
# sudo, so the session that asks for it never sees the Proxmox token, the seal key, the AppRole IDs,
# the recovery shares or the VM's SSH key. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/secrets-store.sh plan|apply|configure|recovery|status|destroy
# plan, apply, destroy: OpenTofu on hosts/terraform/home/secrets-store with the agents' Proxmox token.
# configure: the openbao playbook over SSH. recovery: makes the recovery shares once (self-
# initialization makes none) into the keys folder. status: sys/health, which holds no secret.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | configure | recovery | status | destroy) action=$1 ;;
  *) echo "usage: secrets-store plan|apply|configure|recovery|status|destroy" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
env_keys=$keys/dev   # dev only; prod follows D-0035 rule 3 with its own folder
work=/var/lib/agent-box
repo=$work/checkouts/secrets-store   # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/secrets-store
settings=$work/secrets-store.json   # private values the agent_box role writes from the inventory
state=$work/state/secrets-store.tfstate
plan=$work/state/secrets-store.tfplan
vars=$work/state/secrets-store.tfvars.json
sshkey=$env_keys/secrets-store-ssh
cacert=$env_keys/secrets-store-ca.crt
export HOME=$work PATH=/usr/local/libexec/agent-box/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/secrets-store TF_IN_AUTOMATION=1 ANSIBLE_COLLECTIONS_PATH=/usr/local/libexec/agent-box/collections ANSIBLE_HOME=$work/ansible-home

[[ -f $settings ]] || { echo "secrets-store: $settings is missing; set agent_box_secrets_store in the inventory and run the agent_box role" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

# Only reviewed code on main runs with the keys, never a checkout a session can edit. One run at a time.
exec 9>"$work/state/secrets-store.lock"
flock -n 9 || { echo "secrets-store: another secrets-store run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "secrets-store: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# The store's keys, made here the first time and never printed: the VM's SSH key, the 32-byte static
# seal key (D-0038 rule 4) and the admin AppRole's IDs (rule 6). A file that exists is never replaced:
# a new seal key would make every snapshot unreadable.
mkdir -p "$env_keys"
[[ -f $sshkey ]] || ssh-keygen -q -t ed25519 -N "" -C "keys@agent-box secrets-store" -f "$sshkey"
[[ -f $env_keys/openbao-seal.key ]] || openssl rand -out "$env_keys/openbao-seal.key" 32
[[ -f $env_keys/openbao-admin-role-id ]] || openssl rand -hex 24 > "$env_keys/openbao-admin-role-id"
[[ -f $env_keys/openbao-admin-secret-id ]] || openssl rand -hex 24 > "$env_keys/openbao-admin-secret-id"

tofu_run() {
  python3 -I - "$settings" "$sshkey.pub" "$repo" "$vars" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
json.dump({
    "proxmox_node_name": s["proxmox_node_name"],
    "vnet": s["vnet"],
    "vlans_file": sys.argv[3] + "/hosts/ansible/inventories/home/group_vars/all/vlans.yml",
    "template_vm_id": s["template_vm_id"],
    "ssh_public_key": open(sys.argv[2]).read().strip(),
    "store": {k: s[k] for k in ("name", "vm_id", "address", "cores", "memory_mb", "disk_gb")},
}, open(sys.argv[4], "w"))
PY
  # PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN (agent@pve!dev).
  set -a
  # shellcheck source=/dev/null
  . "$keys/proxmox-dev.env"
  set +a
  tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
  tofu init -input=false -backend-config="path=$state" >/dev/null
  case $action in
    plan) tofu plan -input=false -var-file="$vars" -out="$plan" ;;
    apply)
      [[ -f $plan ]] || { echo "secrets-store: no saved plan; run secrets-store plan first" >&2; exit 1; }
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
    destroy)
      tofu plan -destroy -input=false -var-file="$vars" -out="$plan"
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
  esac
}

configure() {
  local extra inventory
  extra=$(mktemp --suffix=.json "$work/state/secrets-store-extra.XXXXXX")
  inventory=$(mktemp --suffix=.json "$work/state/secrets-store-inventory.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -f '$extra' '$inventory'" EXIT
  python3 -I - "$settings" "$inventory" "$extra" "$env_keys" "$cacert" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
k = sys.argv[4]
json.dump({"openbao": {"hosts": {"openbao_vm": {
    "ansible_host": s["address"], "ansible_user": s.get("admin_user", "admin")}}}}, open(sys.argv[2], "w"))
json.dump({
    "openbao_hostname": s["name"],
    "openbao_address": s["address"],
    "openbao_box_address": s["box_address"],
    "openbao_seal_key_id": str(s.get("seal_key_id", "1")),
    "openbao_seal_key_src": k + "/openbao-seal.key",
    "openbao_admin_role_id_src": k + "/openbao-admin-role-id",
    "openbao_admin_secret_id_src": k + "/openbao-admin-secret-id",
    "openbao_cacert_dest": sys.argv[5],
}, open(sys.argv[3], "w"))
PY
  mkdir -p "$work/.ssh"
  cd "$repo/hosts/ansible"
  ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/.ssh/known_hosts" \
    ansible-playbook -i "$inventory" --private-key "$sshkey" -e "@$extra" playbooks/openbao.yml
}

addr() { echo "https://$(setting address)"; }

status() {
  curl -sS --fail-with-body --cacert "$cacert" "$(addr)/v1/sys/health"
  echo
}

# An admin token for one call. The secret ID goes to curl on stdin, never as an argument.
admin_token() {
  python3 -I -c 'import json,sys; print(json.dumps({"role_id": open(sys.argv[1]).read().strip(), "secret_id": open(sys.argv[2]).read().strip()}))' \
    "$env_keys/openbao-admin-role-id" "$env_keys/openbao-admin-secret-id" |
    curl -sS --fail-with-body --cacert "$cacert" -X POST --data @- "$(addr)/v1/auth/approle/login" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])'
}

recovery() {
  local out=$env_keys/openbao-recovery.json token
  [[ ! -s $out ]] || { echo "secrets-store: recovery shares exist already ($out); nothing done" >&2; exit 1; }
  token=$(admin_token)
  # 3 shares, any 2 make a root token for break-glass (D-0038 rule 5). Written only to the keys folder.
  printf 'header = "X-Vault-Token: %s"\n' "$token" |
    curl -sS --fail-with-body --cacert "$cacert" -K - -X POST \
      --data '{"secret_shares":3,"secret_threshold":2}' "$(addr)/v1/sys/rotate/recovery/init" > "$out.part"
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("keys") or d.get("data",{}).get("keys"), "no shares in the reply"' "$out.part" ||
    { echo "secrets-store: the reply held no recovery shares; kept at $out.part for checking" >&2; exit 1; }
  mv "$out.part" "$out"
  printf 'header = "X-Vault-Token: %s"\n' "$token" |
    curl -sS --cacert "$cacert" -K - -X POST "$(addr)/v1/auth/token/revoke-self" >/dev/null
  echo "secrets-store: recovery shares written to the keys folder (not printed)"
}

case $action in
  configure) configure ;;
  status) status ;;
  recovery) recovery ;;
  *) tofu_run ;;
esac
