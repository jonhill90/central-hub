#!/bin/bash
# /usr/local/libexec/agent-box/lab-test.sh: the lab test copy, VM 256, a nested Proxmox VE 9 on dev that will hold
# its own SDN, OPNsense and connector container (docs/specs/2026-11-lab-test-copy.md,
# docs/runbooks/build-the-lab-test-copy.md). It runs as user `keys` through sudo, so the session that asks for it
# never sees the Proxmox token. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/lab-test.sh plan|apply|check|destroy|log
# plan: the guards (dev down, no dev rebuild running, VM 257 gone, free memory and box disk), then download and
#   check the Proxmox VE ISO, write the answer file, bake it into a copy of the ISO with the pinned
#   proxmox-auto-install-assistant (--fetch-from iso), and save an OpenTofu plan for hosts/terraform/home/lab-test.
# apply: apply only that saved plan. The VM starts, its installer picks "Automated Installation" after 10 seconds,
#   installs, and reboots into the installed system from the disk.
# check: wait for SSH as root with the box's key, then read the Proxmox VE version and whether the copy's CPU shows
#   vmx or svm and has /dev/kvm, which its own guests need. Changes nothing.
# destroy: destroy VM 256 only. The token cannot delete files on Proxmox's local storage, so the prepared ISO stays
#   in the state and on local for the next build, which reuses it while the answer is unchanged; destroy lists it.
# log: the last run's log, then VM 256's Proxmox state, read-only.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | check | destroy | log) action=$1 ;;
  *) echo "usage: lab-test plan|apply|check|destroy|log" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
repo=$work/checkouts/lab-test        # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/lab-test
settings=$work/lab-test.json         # private values the agent_box role writes from the inventory
state=$work/state/lab-test.tfstate
plan=$work/state/lab-test.tfplan
vars=$work/state/lab-test.tfvars.json
files=$work/lab-test                 # the source ISO, the answer, the prepared ISOs; kept for the next build
iso_res=proxmox_virtual_environment_file.installer
vm_res=proxmox_virtual_environment_vm.host
sshkey=$keys/lab-test-ssh
logfile=$work/state/lab-test.log
export HOME=$work PATH=/usr/local/libexec/agent-box/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin
export TF_DATA_DIR=$work/tofu-data/lab-test TF_IN_AUTOMATION=1
py=/usr/local/libexec/agent-box/ansible-venv/bin/python3   # has PyYAML, for the shared VLAN file
answer_py=$libexec/lab-test-answer.py
assistant=$libexec/proxmox-auto-install-assistant           # the role installs it from the pinned .deb

VMID=256
OPNSENSE_TEST_VMID=257
# Proxmox VE 9.2-1, the release the copy installs; the sha256 is the ISO's line in
# https://enterprise.proxmox.com/iso/SHA256SUMS (read 2026-11-18).
ISO_NAME=proxmox-ve_9.2-1.iso
ISO_URL=https://enterprise.proxmox.com/iso/$ISO_NAME
ISO_SHA256=4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c
# What plan needs free in the box's work folder: the source ISO and one prepared copy, plus room.
DISK_NEED_MB=5120

if [[ $action == log ]]; then
  cat "$logfile" 2>/dev/null || echo "lab-test: no log yet"
  [[ -f $settings ]] || exit 0
fi
[[ -f $settings ]] || { echo "lab-test: $settings is missing; set agent_box_lab_test in the inventory and run the agent_box role" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

# One Proxmox API call with the agents' token, as the dev rebuild makes them; the token goes to curl on stdin.
px_api() { # path
  # shellcheck source=/dev/null
  ( set -a; . "$keys/proxmox-dev.env"; set +a
    insecure=(); case "${PROXMOX_VE_INSECURE:-}" in true|1) insecure=(-k) ;; esac
    printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
      curl -sS --fail --max-time 30 "${insecure[@]}" -K - "${PROXMOX_VE_ENDPOINT%/}/api2/json/$1" )
}

if [[ $action == log ]]; then
  echo "lab-test: status at $(date -u +%FT%TZ)"
  px_api "nodes/$(setting proxmox_node_name)/qemu/$VMID/status/current" | python3 -I -c 'import json, sys
d = json.load(sys.stdin)["data"]
print("lab-test: VM %s is %s, uptime %ss, memory %s of %s MiB" % (sys.argv[1], d.get("status"), d.get("uptime", 0),
      d.get("mem", 0) // 1048576, d.get("maxmem", 0) // 1048576))' "$VMID" 2>/dev/null \
    || echo "lab-test: VM $VMID is not on the node, or the token cannot read it"
  exit 0
fi

exec 9>"$work/state/lab-test.lock"
flock -n 9 || { echo "lab-test: another lab-test run is going; try again when it ends" >&2; exit 1; }
exec > >(tee "$logfile") 2>&1
echo "lab-test: $action at $(date -u +%FT%TZ)"
mkdir -p "$files"
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "lab-test: central-hub $(git -C "$repo" rev-parse --short HEAD)"
vlans=$repo/hosts/ansible/inventories/home/group_vars/all/vlans.yml
[[ -f $sshkey ]] || ssh-keygen -q -t ed25519 -N "" -C "keys@agent-box lab-test" -f "$sshkey"
addr=$(setting address)

# The copy never runs beside dev or the OPNsense test VM: the node has the memory for one of the three
# (docs/specs/2026-11-lab-test-copy.md). Dev's state must hold no resource, dev's tfvars must not declare VM 256,
# no dev rebuild may run, VM 257 must not exist, and the node must have the copy's memory plus the margin.
guards() {
  local n guests node free need
  if [[ -s $work/state/dev-vms.tfstate ]]; then
    n=$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("resources", [])))' "$work/state/dev-vms.tfstate")
    [[ $n == 0 ]] || { echo "lab-test: refused, dev's state holds $n resources; tear dev down first (rebuild teardown)"; return 1; }
  fi
  if grep -Eq "(vm_id|vmid)[[:space:]]*=[[:space:]]*$VMID([^0-9]|$)" "$keys/dev-vms.tfvars" 2>/dev/null; then
    echo "lab-test: refused, dev-vms.tfvars declares VM $VMID"; return 1
  fi
  exec 8>"$work/state/rebuild.lock"
  flock -n 8 || { echo "lab-test: refused, a dev rebuild run is going"; return 1; }
  guests=$(px_api "cluster/resources?type=vm") || { echo "lab-test: refused, the guest list could not be read"; return 1; }
  if python3 -I -c 'import json,sys; sys.exit(0 if any(g.get("vmid") == int(sys.argv[1]) for g in json.load(sys.stdin)["data"]) else 1)' \
      "$OPNSENSE_TEST_VMID" <<<"$guests"; then
    echo "lab-test: refused, VM $OPNSENSE_TEST_VMID (the OPNsense test) exists; run opnsense-test destroy first"; return 1
  fi
  node=$(setting proxmox_node_name)
  need=$(( $(setting memory_mb) + 2048 ))
  free=$(px_api "nodes/$node/status" | python3 -I -c 'import json,sys
m = json.load(sys.stdin)["data"]["memory"]
print((m["available"] if m.get("available") is not None else m["total"] - m["used"]) // 1048576)') \
    || { echo "lab-test: refused, the node's free memory could not be read"; return 1; }
  echo "lab-test: preflight: node free memory $free MiB, need $need MiB (the copy plus the 2048 MiB margin)"
  (( free >= need )) || { echo "lab-test: refused, short on memory"; return 1; }
  free=$(df -Pm "$files" | awk 'NR == 2 {print $4}')
  echo "lab-test: preflight: box disk free $free MiB in $files, need $DISK_NEED_MB MiB"
  (( free >= DISK_NEED_MB )) || { echo "lab-test: refused, short on box disk"; return 1; }
}

# The Proxmox VE ISO, checked against its pin.
source_iso() {
  local iso=$files/$ISO_NAME
  [[ -f $iso ]] && return 0
  curl -sS --fail --max-time 3600 -o "$iso.part" "$ISO_URL"
  echo "$ISO_SHA256  $iso.part" | sha256sum -c --quiet - || { rm -f "$iso.part"; echo "lab-test: the ISO does not match its pin; nothing built"; return 1; }
  mv "$iso.part" "$iso"
  echo "lab-test: $ISO_NAME checked against $ISO_SHA256"
}

# The answer, then the prepared ISO. Root's hash is of a random password no one keeps; the hash file stays, so the
# same settings give the same answer. A prepared ISO is kept under the hash of what made it (the source ISO, the
# assistant and the answer), so an unchanged answer reuses the same file, and its upload is the same file on local,
# which the token can't delete.
prepared() {
  [[ -f $files/root.hash ]] || openssl rand -base64 48 | openssl passwd -6 -stdin > "$files/root.hash"
  "$py" -I "$answer_py" answer "$settings" "$vlans" "$sshkey.pub" "$files/root.hash" "$files/answer.toml"
  "$assistant" validate-answer "$files/answer.toml"
  local key
  key=$(cat <(echo "$ISO_SHA256") <(sha256sum "$assistant") "$files/answer.toml" | sha256sum | cut -c1-16)
  iso_out=$files/prepared-$key.iso
  if [[ -f $iso_out ]]; then
    echo "lab-test: the answer is unchanged; the prepared ISO is reused"
    return 0
  fi
  rm -rf "$files"/prepared-*.iso "$files"/*.part "$files/tmp"   # one prepared copy on the box at a time
  mkdir -p "$files/tmp"
  # The assistant's scratch files go beside the ISO, not to /tmp. It writes to a name that ends in .iso, and the
  # name gets its hash only once the write has finished.
  TMPDIR=$files/tmp "$assistant" prepare-iso "$files/$ISO_NAME" --fetch-from iso --answer-file "$files/answer.toml" \
    --output "$files/prepared-next.iso"
  mv "$files/prepared-next.iso" "$iso_out"
  rm -rf "$files/tmp"
  echo "lab-test: prepared $(basename "$iso_out") (the installer's boot menu picks Automated Installation after 10 seconds)"
}

write_vars() {
  python3 -I - "$settings" "$iso_out" "$vars" <<'PY'
import hashlib, json, sys
s = json.load(open(sys.argv[1]))
h = hashlib.sha256()
with open(sys.argv[2], "rb") as f:
    for b in iter(lambda: f.read(1 << 20), b""):
        h.update(b)
json.dump({
    "proxmox_node_name": s["proxmox_node_name"], "vnet": "dev",
    "installer_iso_path": sys.argv[2], "installer_iso_sha256": h.hexdigest(),
    "vm": {"name": s["name"], "vm_id": 256, "cores": s["cores"], "memory_mb": s["memory_mb"], "disk_gb": s["disk_gb"]},
}, open(sys.argv[3], "w"))
PY
}

tofu_run() {
  if [[ $action == destroy && ! -f $vars ]]; then
    [[ ! -s $state ]] || { echo "lab-test: the state holds resources but $vars is gone; run plan, then destroy" >&2; exit 1; }
    echo "lab-test: nothing to destroy"; return 0
  fi
  set -a
  # shellcheck source=/dev/null
  . "$keys/proxmox-dev.env"
  set +a
  tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
  tofu init -input=false -backend-config="path=$state" >/dev/null
  local held
  held=$(tofu state list 2>/dev/null || true)
  case $action in
    plan)
      # A plan while the VM is in the state could replace the installer ISO, a delete the token can't make.
      if grep -qx "$vm_res" <<<"$held"; then
        echo "lab-test: refused, VM $VMID is in the state; run lab-test destroy first" >&2; exit 1
      fi
      source_iso; prepared; write_vars
      # An installer ISO in the state is an earlier build's. With the same hash it is the same file and is reused.
      # With another hash it leaves the state and its file stays on local; the new ISO is a new file.
      if grep -qx "$iso_res" <<<"$held"; then
        local want have
        want="lab-test-$VMID-pve-auto-$(sha256sum "$iso_out" | cut -c1-12).iso"
        have=$(tofu state show -no-color "$iso_res" | sed -n 's/^ *id *= *"local:iso\/\(.*\)"$/\1/p')
        if [[ $have == "$want" ]]; then
          echo "lab-test: the installer ISO is unchanged; the earlier build's file is reused"
        else
          tofu state rm "$iso_res" >/dev/null
          echo "lab-test: the installer ISO changed; the earlier one left the state and its file stays on local"
        fi
      fi
      tofu plan -input=false -var-file="$vars" -out="$plan"
      ;;
    apply)
      [[ -f $plan ]] || { echo "lab-test: no saved plan; run lab-test plan first" >&2; exit 1; }
      tofu apply -input=false "$plan"
      rm -f "$plan"
      echo "lab-test: VM $VMID started; the automated install runs now. Run lab-test check."
      ;;
    destroy)
      # Only the VM: the token has no Datastore.Allocate on local (hosts/terraform/home/bootstrap/agent-access.sh).
      if grep -qx "$vm_res" <<<"$held"; then
        tofu plan -destroy -input=false -var-file="$vars" -target="$vm_res" -out="$plan"
        tofu apply -input=false "$plan"
        rm -f "$plan"
      fi
      if grep -qx "$iso_res" <<<"$held"; then
        kept_iso=$(tofu state show -no-color "$iso_res" | sed -n 's/^ *id *= *"\(local:iso\/.*\)"$/\1/p')
      fi
      ;;
  esac
}

# What destroy leaves on the node's local storage, for the owner to remove. A read of the storage's content list.
leftovers() {
  px_api "nodes/$(setting proxmox_node_name)/storage/local/content" | python3 -I -c 'import json, sys
for v in json.load(sys.stdin)["data"]:
    i = v.get("volid", "")
    if i and i == sys.argv[2]:
        print("lab-test: kept on local for the next build, which reuses it while the answer is unchanged: " + i)
    elif i.startswith("local:iso/lab-test-%s-pve-auto-" % sys.argv[1]):
        print("lab-test: left on local for the owner to remove: " + i)' "$VMID" "${kept_iso:-}" \
    || echo "lab-test: the node's local storage could not be listed"
}

vm() { ssh -i "$sshkey" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$files/known_hosts" "root@$addr" "$@"; }

# The install takes some minutes after apply; wait up to 30 for the installed system's SSH.
check() {
  local _ up=
  for _ in $(seq 1 180); do vm true 2>/dev/null && { up=1; break; }; sleep 10; done
  [[ -n $up ]] || { echo "lab-test: no SSH to $addr after 30 minutes; run lab-test log, then destroy and report it"; return 1; }
  vm pveversion
  local flags
  flags=$(vm "grep -cE '(vmx|svm)' /proc/cpuinfo" || true)
  if [[ ${flags:-0} == 0 ]] || ! vm 'test -c /dev/kvm'; then
    echo "lab-test: stopped, the copy's CPU shows no vmx or svm, or it has no /dev/kvm, so its own guests would run"
    echo "lab-test: without KVM. The host's kvm module needs nested on; turning it on stops every guest on the host,"
    echo "lab-test: so it is the owner's call (Proxmox VE wiki, Nested Virtualization). Destroy, then report it."
    return 1
  fi
  echo "lab-test: the copy's CPU shows vmx or svm on $flags threads and it has /dev/kvm; its own guests can use KVM"
}

case $action in
  plan) guards; tofu_run ;;
  apply) guards; tofu_run ;;
  check) check ;;
  destroy)
    tofu_run
    rm -f "$files/known_hosts" "$files"/*.part
    echo "lab-test: VM $VMID destroyed"
    leftovers
    ;;
esac
