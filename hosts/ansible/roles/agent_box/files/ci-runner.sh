#!/bin/bash
# /usr/local/libexec/agent-box/ci-runner.sh: build and set up the notebook's self-hosted CI runner
# (docs/runbooks/set-up-the-ci-runner.md). It runs as user `keys` through sudo, so the session that
# asks for it never sees the Proxmox token, the runner's SSH key or the GitHub App key. Installed
# by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/ci-runner.sh plan|apply|configure|destroy
# plan, apply, destroy: OpenTofu on hosts/terraform/home/ci-runner with the agents' Proxmox token.
# configure: the ci_runner playbook over SSH, with a one-hour registration token minted from the
# GitHub App, narrowed to the one repository and the one permission it needs.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | configure | destroy) action=$1 ;;
  *) echo "usage: ci-runner plan|apply|configure|destroy" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
repo=$work/central-hub
folder=$repo/hosts/terraform/home/ci-runner
settings=$work/ci-runner.json   # private values the agent_box role writes from the inventory
state=$work/state/ci-runner.tfstate
plan=$work/state/ci-runner.tfplan
vars=$work/state/ci-runner.tfvars.json
sshkey=$keys/ci-runner-ssh
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin TF_DATA_DIR=$work/tofu-data/ci-runner TF_IN_AUTOMATION=1

[[ -f $settings ]] || { echo "ci-runner: $settings is missing; set agent_box_ci_runner in the inventory and run the agent_box role" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

# Only reviewed code on main runs with the keys, never a checkout a session can edit.
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "ci-runner: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# The runner's own SSH key, made here the first time. Only its public half leaves this folder.
[[ -f $sshkey ]] || ssh-keygen -q -t ed25519 -N "" -C "keys@agent-box ci-runner" -f "$sshkey"

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
    "runner": {k: s[k] for k in ("name", "vm_id", "address", "cores", "memory_mb", "disk_gb")},
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
      [[ -f $plan ]] || { echo "ci-runner: no saved plan; run ci-runner plan first" >&2; exit 1; }
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

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# A registration token for the one repository, from the GitHub App "Central Hub Agents". The App
# needs the repository permission Administration (write), which GitHub requires for this call; the
# installation token asked for here is cut down to that one repository and that one permission.
registration_token() {
  local app_id owner name now jwt inst tok
  app_id=$(setting github_app_id)
  owner=$(setting repo_owner)
  name=$(setting repo_name)
  now=$(date +%s)
  jwt="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$app_id" | b64url)"
  jwt="$jwt.$(printf '%s' "$jwt" | openssl dgst -sha256 -sign "$keys/github-app.pem" | b64url)"
  api() { curl -fsS -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }
  inst=$(api -H "Authorization: Bearer $jwt" "https://api.github.com/repos/$owner/$name/installation" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  tok=$(api -X POST -H "Authorization: Bearer $jwt" "https://api.github.com/app/installations/$inst/access_tokens" \
    -d "{\"repositories\":[\"$name\"],\"permissions\":{\"administration\":\"write\"}}" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["token"])')
  api -X POST -H "Authorization: Bearer $tok" "https://api.github.com/repos/$owner/$name/actions/runners/registration-token" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["token"])'
}

configure() {
  local extra inventory
  extra=$(mktemp "$work/state/ci-runner-extra.XXXXXX")
  inventory=$(mktemp "$work/state/ci-runner-inventory.XXXXXX")
  trap 'rm -f "$extra" "$inventory"' EXIT
  python3 -I - "$settings" "$inventory" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
json.dump({"ci_runner": {"hosts": {"ci_runner_vm": {
    "ansible_host": s["address"], "ansible_user": "admin", "ci_runner_hostname": s["name"]}}}},
    open(sys.argv[2], "w"))
PY
  # A runner that is registered already needs no token, so a failed mint only warns; the role
  # stops if the runner isn't registered and has no token.
  local token
  token=$(registration_token) || { echo "ci-runner: no registration token (does the App have Administration: write?)" >&2; token=""; }
  printf '{"ci_runner_registration_token": "%s"}\n' "$token" > "$extra"
  mkdir -p "$work/.ssh"
  cd "$repo/hosts/ansible"
  # A rebuilt runner has a new host key, and the run stops on it: remove its line from
  # $work/.ssh/known_hosts after checking (docs/runbooks/set-up-the-ci-runner.md).
  ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/.ssh/known_hosts" \
    ansible-playbook -i "$inventory" --private-key "$sshkey" -e "@$extra" playbooks/ci-runner.yml
}

case $action in
  plan | apply | destroy) tofu_run ;;
  configure) configure ;;
esac
