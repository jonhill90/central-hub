#!/bin/bash
# /usr/local/libexec/agent-box/lab-test.sh: the lab test copy, VM 256, a nested Proxmox VE 9 on dev that will hold
# its own SDN, OPNsense and connector container (docs/specs/2026-11-lab-test-copy.md,
# docs/runbooks/build-the-lab-test-copy.md). It runs as user `keys` through sudo, so the session that asks for it
# never sees the Proxmox token. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/lab-test.sh plan|apply|check|host|lab|firstboot|destroy|log
# plan: the guards (dev down, no dev rebuild running, VM 257 gone, free memory and box disk), then download and
#   check the Proxmox VE ISO, write the answer file, bake it into a copy of the ISO with the pinned
#   proxmox-auto-install-assistant (--fetch-from iso), and save an OpenTofu plan for hosts/terraform/home/lab-test.
# apply: apply only that saved plan. The VM starts, its installer picks "Automated Installation" after 10 seconds,
#   installs, and reboots into the installed system from the disk.
# check: wait for SSH as root with the box's key, then read the Proxmox VE version and whether the copy's CPU shows
#   vmx or svm and has /dev/kvm, which its own guests need. Changes nothing.
# host: inside the copy, as on a fresh real host (docs/runbooks/set-up-proxmox-host.md steps 1 and 6b, then
#   docs/runbooks/set-up-lab-network-and-firewall.md step 1): the no-subscription apt repository, iac-access.sh, the
#   copy's own iac@pve!apply token (kept on the box, removed by destroy), then playbooks/proxmox-host.yml --tags vmbr1
#   against the copy with an inventory the wrapper writes, then the OPNsense nano image and the Debian 13 template
#   inside the copy, each checked against its pin. Safe to run again.
# lab: inside the copy, docs/runbooks/set-up-lab-network-and-firewall.md steps 2 to 4: the network, firewall and
#   remote-access run folders against the copy's own API, each with its own state on the box, then
#   playbooks/proxmox-host.yml --tags mgmt. Each folder's second plan must show no changes. Safe to run again.
# firstboot: inside the copy, set-up-lab-network-and-firewall.md step 5 with no person: over VM 100's serial console,
#   as root on the copy, sign in, run hosts/ansible/bootstrap/opnsense-first-boot.php (mgmt VLAN, LAN, WAN, root's
#   password, kept on the box), reboot VM 100, and wait for the mgmt gateway to answer. Safe to run again.
# destroy: destroy VM 256 only. The token cannot delete files on Proxmox's local storage, so the prepared ISO stays
#   in the state and on local for the next build, which reuses it while the answer is unchanged; destroy lists it.
# log: the last run's log, then VM 256's Proxmox state, read-only.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | check | host | lab | firstboot | destroy | log) action=$1 ;;
  *) echo "usage: lab-test plan|apply|check|host|lab|firstboot|destroy|log" >&2; exit 2 ;;
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
console_py=$libexec/lab-test-console.py
assistant=$libexec/proxmox-auto-install-assistant           # the role installs it from the pinned .deb

VMID=256
OPNSENSE_TEST_VMID=257
# Proxmox VE 9.2-1, the release the copy installs; the sha256 is the ISO's line in
# https://enterprise.proxmox.com/iso/SHA256SUMS (read 2026-11-18).
ISO_NAME=proxmox-ve_9.2-1.iso
ISO_URL=https://enterprise.proxmox.com/iso/$ISO_NAME
ISO_SHA256=4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c
# The images the copy's run folders need (docs/runbooks/stage-lab-images-on-proxmox.md), fetched inside the copy.
# OPNsense 26.1.6 nano, the newest 26.1 image (the runbook's pick); the sha256 is its line in
# https://pkg.opnsense.org/releases/26.1/OPNsense-26.1.6-checksums-amd64.sha256 (read 2026-11-18).
NANO_IMG=OPNsense-26.1.6-nano-amd64.img
NANO_URL=https://pkg.opnsense.org/releases/26.1/$NANO_IMG.bz2
NANO_BZ2_SHA256=3c16267c791abfc3e41d5249fcb0c245c03cb91e2f1aa4d53017f0f3454d03a1
# Debian 13 for CT 900, from Proxmox's template index (aplinfo-pve-9.dat, read 2026-11-18), which pveam checks
# itself; the wrapper checks the same sha512 again.
CT_TEMPLATE=debian-13-standard_13.6-1_amd64.tar.zst
CT_TEMPLATE_SHA512=4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b
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

# The answer, then the prepared ISO. Root's hash is of a random password kept only on the box, for lab's sign-in as
# root@pam to the copy's own API; the hash and the password stay, so the same settings give the same answer. A prepared ISO is kept under the hash of what made it (the source ISO, the
# assistant and the answer), so an unchanged answer reuses the same file, and its upload is the same file on local,
# which the token can't delete.
prepared() {
  if [[ ! -s $files/root.hash || ! -s $files/root.pass ]]; then
    openssl rand -base64 32 > "$files/root.pass"
    openssl passwd -6 -stdin < "$files/root.pass" > "$files/root.hash"
  fi
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
wait_ssh() {
  local _
  for _ in $(seq 1 180); do vm true 2>/dev/null && return 0; sleep 10; done
  echo "lab-test: no SSH to $addr after 30 minutes; run lab-test log, then destroy and report it"; return 1
}

check() {
  wait_ssh
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

# The copy's host steps, the same ones a person runs on a fresh real host. The apt step is the runbook's step 1
# (set-up-proxmox-host.md lines 97-125): "Enabled: no" in each enterprise stanza, and the no-subscription repository.
host() {
  wait_ssh
  vm 'sh -s' <<'SH'
set -eu
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  [ -f "$f" ] || continue
  # One stanza per file on a fresh install; with more, "Enabled: no" at the end would cover only the last.
  [ "$(grep -c '^Types:' "$f")" = 1 ] || { echo "lab-test: $f holds more than one stanza; not changed"; exit 1; }
  grep -q '^Enabled: no$' "$f" || printf 'Enabled: no\n' >> "$f"
done
cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
apt-get update -q
SH
  echo "lab-test: the copy's apt uses the no-subscription repository"
  # iac-access.sh, the token, then the script again, as set-up-proxmox-host.md step 6b gives it. The token is the
  # copy's own: it reaches only the copy, and destroy removes the file.
  scp -q -i "$sshkey" -o BatchMode=yes -o UserKnownHostsFile="$files/known_hosts" \
    "$repo/hosts/terraform/home/bootstrap/iac-access.sh" "root@$addr:/root/iac-access.sh"
  vm 'sh /root/iac-access.sh'
  if [[ ! -s $files/copy-token ]]; then
    # A token whose secret is lost (the file is gone) can't be read again; replace it.
    vm 'pveum user token remove iac@pve apply 2>/dev/null || true'
    vm "pveum user token add iac@pve apply --privsep 1 --expire $(date -d '+2 days' +%s) --output-format json" \
      | python3 -I -c 'import json,sys; print("iac@pve!apply=" + json.load(sys.stdin)["value"])' > "$files/copy-token.part"
    mv "$files/copy-token.part" "$files/copy-token"
    echo "lab-test: made the copy's iac@pve!apply token, valid 2 days"
  fi
  vm 'sh /root/iac-access.sh'
  vm 'pveum user token permissions iac@pve apply --output-format json' | python3 -I -c 'import json,sys
print("lab-test: the copy token reaches %d paths" % len(json.load(sys.stdin)))'
  # The copy's inventory: the real inventory's shape (hosts.example.yml), the copy's own values.
  mkdir -p "$files/inventory/group_vars/all"
  cp "$vlans" "$files/inventory/group_vars/all/vlans.yml"
  "$py" -I "$answer_py" inventory "$settings" "$vlans" "$sshkey" "$files/known_hosts" "$files/inventory/hosts.yml"
  # The collections the role installs for the rebuild wrappers (rebuild.sh), from the same requirements file.
  ( cd "$repo/hosts/ansible"
    ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home \
      ansible-playbook -i "$files/inventory" playbooks/proxmox-host.yml --tags vmbr1 )
  vm 'ip -br link show vmbr1'
  images
}

# The runbook's steps 1, 2, 3 and 5 inside the copy: storage local takes import, the nano image checked against its
# pin and unpacked under import/, and the Debian 13 template. Each is skipped when it is already there.
images() {
  vm "NANO_IMG=$NANO_IMG NANO_URL=$NANO_URL NANO_SHA=$NANO_BZ2_SHA256 CT=$CT_TEMPLATE CT_SHA=$CT_TEMPLATE_SHA512 sh -s" <<'SH'
set -eu
# storage.cfg: a "dir: local" line, then its indented options (a fresh install has "content iso,vztmpl,backup").
content=$(awk '/^dir: local$/ {f=1; next} /^[a-z]/ {f=0} f && $1 == "content" {print $2}' /etc/pve/storage.cfg)
[ -n "$content" ] || { echo "lab-test: storage local has no content line in /etc/pve/storage.cfg"; exit 1; }
case ",$content," in *,import,*) ;; *) pvesm set local --content "$content,import" ;; esac
command -v bzip2 >/dev/null || apt-get install -y -q bzip2
mkdir -p /var/lib/vz/import
cd /var/lib/vz/import
if [ ! -f "$NANO_IMG" ]; then
  curl -fsS --max-time 1800 -o "$NANO_IMG.bz2.part" "$NANO_URL"
  echo "$NANO_SHA  $NANO_IMG.bz2.part" | sha256sum -c --quiet - || { rm -f "$NANO_IMG.bz2.part"; echo "lab-test: the nano image does not match its pin"; exit 1; }
  bzip2 -dc "$NANO_IMG.bz2.part" > "$NANO_IMG.part" && mv "$NANO_IMG.part" "$NANO_IMG" && rm -f "$NANO_IMG.bz2.part"
fi
if [ ! -f "/var/lib/vz/template/cache/$CT" ]; then
  pveam update
  pveam download local "$CT"
fi
echo "$CT_SHA  /var/lib/vz/template/cache/$CT" | sha512sum -c --quiet - || { echo "lab-test: the Debian 13 template does not match its pin"; exit 1; }
pvesm list local --content import | grep -F "local:import/$NANO_IMG"
pveam list local | grep -F "local:vztmpl/$CT"
SH
  echo "lab-test: the copy holds local:import/$NANO_IMG and local:vztmpl/$CT_TEMPLATE"
}

# One run folder against the copy's own API, with its own state and plan on the box. The endpoint is the copy's
# address, which the helper checks is a host on dev, where the real host's API is not. The copy's API certificate is
# signed by its own CA and names its address (pve-cluster src/PVE/Cluster/Setup.pm, gen_pve_ssl_cert), so the
# provider trusts that CA and nothing else (Go reads SSL_CERT_FILE and SSL_CERT_DIR; bpg 0.116.0 sets no roots).
lab_folder() { # folder
  local dir=$repo/hosts/terraform/home/$1 out=$files/state/$1 rc=0
  (
    export TF_DATA_DIR=$work/tofu-data/lab-test-$1
    t() { /usr/local/bin/tofu -chdir="$dir" "$@"; }
    t init -input=false -backend-config="path=$out.tfstate" >/dev/null
    export PROXMOX_VE_ENDPOINT=https://$addr:8006/ SSL_CERT_FILE=$files/copy-ca.pem SSL_CERT_DIR=$files/no-ca
    unset PROXMOX_VE_API_TOKEN PROXMOX_VE_USERNAME PROXMOX_VE_PASSWORD PROXMOX_VE_INSECURE
    if [[ $1 == remote-access ]]; then
      # Only root@pam may set CT 900's keyctl and /dev/net/tun, and a token never counts as root@pam (pve-container
      # src/PVE/LXC.pm, check_ct_modify_config_perm), so this folder signs in with root's password.
      PROXMOX_VE_USERNAME=root@pam PROXMOX_VE_PASSWORD=$(head -n 1 "$files/root.pass")
      export PROXMOX_VE_USERNAME PROXMOX_VE_PASSWORD
    else
      PROXMOX_VE_API_TOKEN=$(cat "$files/copy-token")
      export PROXMOX_VE_API_TOKEN
    fi
    t plan -input=false -var-file="$out.tfvars.json" -out="$out.tfplan"
    t apply -input=false "$out.tfplan"
    rm -f "$out.tfplan"
    t plan -input=false -detailed-exitcode -var-file="$out.tfvars.json" >/dev/null || rc=$?
    [[ $rc == 0 ]] || { echo "lab-test: $1: the second plan is not empty (exit $rc); stopped"; exit 1; }
    echo "lab-test: $1 applied in the copy; a second plan shows no changes"
  )
}

# The copy's lab layer, as on a fresh real host after its vmbr1: the SDN, VM 100 (OPNsense, WAN link-down) and CT 900
# from the run folders (set-up-lab-network-and-firewall.md steps 2 and 3), then the host's address on mgmt (step 4).
lab() {
  wait_ssh
  [[ -s $files/copy-token && -f $files/inventory/hosts.yml ]] || { echo "lab-test: run lab-test host first"; return 1; }
  [[ -s $files/root.pass ]] || { echo "lab-test: root's password is not on the box; destroy and build again"; return 1; }
  mkdir -p "$files/state" "$files/no-ca"
  # The copy's CA over SSH, whose host key the box pinned at its first contact with the copy.
  vm 'cat /etc/pve/pve-root-ca.pem' > "$files/copy-ca.pem"
  printf 'header = "Authorization: PVEAPIToken=%s"\n' "$(cat "$files/copy-token")" |
    curl -sS --fail --max-time 30 --cacert "$files/copy-ca.pem" -K - "https://$addr:8006/api2/json/version" >/dev/null \
    || { echo "lab-test: the copy's API does not answer with its own CA and the copy token"; return 1; }
  "$py" -I "$answer_py" layers "$settings" "$vlans" "$NANO_IMG" "$CT_TEMPLATE" "$files/state"
  local f
  for f in network firewall remote-access; do lab_folder "$f"; done
  ( cd "$repo/hosts/ansible"
    ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home \
      ansible-playbook -i "$files/inventory" playbooks/proxmox-host.yml --tags mgmt )
  vm 'ip -br addr show mgmt; qm list; pct list'
}

# The copy's VM 100 has no installer, no SSH and no config on first boot, so the serial console is the only way in
# (lab-test-console.py says why). Root on the copy reaches it as qm terminal does: socat on VM 100's serial0 socket
# (qemu-server src/PVE/CLI/qm.pm, terminal; qemu-server depends on socat, debian/control). OPNsense's own root
# password is new and kept on the box until destroy; the image's default, opnsense, is tried first.
firstboot() {
  wait_ssh
  vm 'qm status 100' | grep -qx 'status: running' || { echo "lab-test: VM 100 is not running in the copy; run lab-test lab first"; return 1; }
  local tag gw prefix
  read -r tag gw prefix < <("$py" -I -c 'import ipaddress, sys, yaml
v = [x for x in yaml.safe_load(open(sys.argv[1]))["lab_vlans"] if x["name"] == "mgmt"][0]
n = ipaddress.ip_network(v["cidr"])
print(v["id"], n.network_address + 1, n.prefixlen)' "$vlans")
  [[ -s $files/opnsense-root.pass ]] || openssl rand -base64 32 > "$files/opnsense-root.pass"
  openssl passwd -6 -stdin < "$files/opnsense-root.pass" > "$files/opnsense-root.hash"
  # net0 is the trunk (vtnet0) and net1 is WAN (vtnet1), in firewall/main.tf's order.
  python3 -I -c 'import json, sys
print(json.dumps({
    "passwords": ["opnsense", open(sys.argv[1]).read().strip()], "dir": "/root/lab-test",
    "files": {"opnsense-first-boot.php": sys.argv[2], "root.hash": sys.argv[3]},
    "commands": ["php opnsense-first-boot.php vtnet0 %s %s vtnet1 root.hash" % (sys.argv[4], sys.argv[5])],
    "reboot": True}))' "$files/opnsense-root.pass" "$repo/hosts/ansible/bootstrap/opnsense-first-boot.php" \
    "$files/opnsense-root.hash" "$tag" "$gw/$prefix" > "$files/console-plan.json"
  local rc=0
  python3 -I "$console_py" "$files/console-plan.json" ssh -i "$sshkey" -o BatchMode=yes -o ConnectTimeout=10 \
    -o UserKnownHostsFile="$files/known_hosts" "root@$addr" "socat UNIX-CONNECT:/var/run/qemu-server/100.serial0 STDIO" || rc=$?
  rm -f "$files/console-plan.json"
  (( rc == 0 )) || return "$rc"
  # The copy has mgmt .2 from lab; the default LAN rules let it ping the gateway.
  local _
  for _ in $(seq 1 60); do
    if vm "ping -c 1 -W 2 $gw >/dev/null"; then echo "lab-test: the mgmt gateway $gw answers from the copy"; return 0; fi
    sleep 10
  done
  echo "lab-test: the mgmt gateway $gw does not answer from the copy after 10 minutes"; return 1
}

case $action in
  plan) guards; tofu_run ;;
  apply) guards; tofu_run ;;
  check) check ;;
  host) host ;;
  lab) lab ;;
  firstboot) firstboot ;;
  destroy)
    tofu_run
    # The copy's token, inventory and run folder states go with it; a new copy gets new ones. Root's password stays
    # with its hash, which the cached prepared ISO holds.
    rm -rf "$files/known_hosts" "$files"/*.part "$files/copy-token" "$files/inventory" "$files/state" "$files/copy-ca.pem" \
      "$files"/opnsense-root.*
    echo "lab-test: VM $VMID destroyed"
    leftovers
    ;;
esac
