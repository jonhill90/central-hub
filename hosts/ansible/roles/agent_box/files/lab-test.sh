#!/bin/bash
# /usr/local/libexec/agent-box/lab-test.sh: the lab test copy, VM 256, a nested Proxmox VE 9 on dev that will hold
# its own SDN, OPNsense and connector container (docs/specs/2026-11-lab-test-copy.md,
# docs/runbooks/build-the-lab-test-copy.md). It runs as user `keys` through sudo, so the session that asks for it
# never sees the Proxmox token. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/lab-test.sh plan|apply|check|host|lab|firstboot|opnsense|signin|wancheck|connector|safety|prove|destroy|log
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
#   password, kept on the box) and then step 6's opnsense-ansible-user.php (the API user, its key and secret kept on
#   the box), then opnsense-ssh-key.php (SSH for root by a key the box makes for this copy, LAN only), reboot VM 100,
#   and wait for the mgmt gateway, the API user and SSH by that key to answer. Safe to run again.
# opnsense: inside the copy, set-up-lab-network-and-firewall.md step 7's playbooks/opnsense.yml against VM 100, from the
#   box through an SSH tunnel to the copy (the copy's mgmt VLAN exists only inside it), with an inventory the wrapper
#   writes; the DNS proof is left out (it asks the gateway directly). A second run must report changed=0, and SSH by
#   firstboot's key must still answer, as firstboot left it.
# signin: docs/runbooks/sign-in-to-opnsense-through-keycloak.md steps 1 to 3 on the copy's VM 100: the pinned
#   os-openid-connect package by pkg add over firstboot's SSH, the plugin's server by hosts/ansible/bootstrap/
#   opnsense-oidc-server.php, and opnsense-test's prover against a throwaway Keycloak on the box, which VM 100 reaches
#   through a reverse forward on that SSH. Its secrets are made for the run and removed when it ends.
# wancheck: inside the copy, step 7's WAN safety check on VM 100, whose WAN is on the copy's portless vmbr9: WAN a DHCP
#   client only (over the console), then a watch for server-type frames from the WAN at link-up and over a reboot.
#   WAN goes down again on any failure.
# connector: inside the copy, CT 900's tailnet client (set-up-tailnet-client-in-ct-900.md steps 1-3) and
#   playbooks/tailnet-connector.yml, never joined to a tailnet; it stops if CT 900 is ever logged in.
# safety: inside the copy, step 8's host firewall (proxmox-safety.yml --tags firewall), off, then on with its dead-man
#   timer, then once more with no change; the timer must end cancelled.
# prove: every step above in order, from plan to safety, then destroy whether they passed or not; each step is its own
#   run of this wrapper under this run's lock and log. One clean prove is one of the spec's two clean runs.
# destroy: destroy VM 256 only. The token cannot delete files on Proxmox's local storage, so the prepared ISO stays
#   in the state and on local for the next build, which reuses it while the answer is unchanged; destroy lists it.
# log: the last run's log, then VM 256's Proxmox state, read-only.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | check | host | lab | firstboot | opnsense | signin | wancheck | connector | safety | prove | destroy | log) action=$1 ;;
  *) echo "usage: lab-test plan|apply|check|host|lab|firstboot|opnsense|signin|wancheck|connector|safety|prove|destroy|log" >&2; exit 2 ;;
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
wan_watch_py=$libexec/lab-test-wan-watch.py
seed_py=$libexec/opnsense-test-seed.py        # opnsense-test's helpers, which signin shares
prove_py=$libexec/opnsense-test-prove.py
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
[[ -f $settings ]] || { echo "lab-test: $settings is missing; run the agent_box role (it writes the file from the role's default or the inventory's agent_box_lab_test)" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

# One Proxmox API call with the agents' token, as the dev rebuild makes them; the token goes to curl on stdin.
px_api() { # path
  # shellcheck source=/dev/null
  ( set -a; . "$keys/proxmox-dev.env"; set +a
    insecure=(); case "${PROXMOX_VE_INSECURE:-}" in true|1) insecure=(-k) ;; esac
    printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
      curl -sS --fail --max-time 30 "${insecure[@]}" -K - "${PROXMOX_VE_ENDPOINT%/}/api2/json/$1" )
}

# The node the copy runs on: the settings' proxmox_node_name when the inventory sets one, otherwise the node the agents'
# token sees at GET /nodes, read at run time and never written to a file in the repository. More or fewer than one node
# is a refusal, because the wrapper will not guess between nodes.
node_name() {
  local n
  n=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("proxmox_node_name", ""))' "$settings") || return 1
  if [[ -z $n ]]; then
    n=$(px_api nodes | python3 -I -c 'import json,sys
names = [x["node"] for x in json.load(sys.stdin)["data"]]
sys.exit("lab-test: GET /nodes shows %d nodes, not one" % len(names)) if len(names) != 1 else print(names[0])') \
      || { echo "lab-test: the node name could not be read from GET /nodes" >&2; return 1; }
  fi
  [[ $n =~ ^[A-Za-z0-9-]+$ ]] || { echo "lab-test: the node name is not a plain host name" >&2; return 1; }
  printf '%s\n' "$n"
}

if [[ $action == log ]]; then
  echo "lab-test: status at $(date -u +%FT%TZ)"
  px_api "nodes/$(node_name)/qemu/$VMID/status/current" | python3 -I -c 'import json, sys
d = json.load(sys.stdin)["data"]
print("lab-test: VM %s is %s, uptime %ss, memory %s of %s MiB" % (sys.argv[1], d.get("status"), d.get("uptime", 0),
      d.get("mem", 0) // 1048576, d.get("maxmem", 0) // 1048576))' "$VMID" 2>/dev/null \
    || echo "lab-test: VM $VMID is not on the node, or the token cannot read it"
  exit 0
fi

# A step of prove runs under prove's lock, log and checkout: its parent is the prove run that named itself. Any other
# run takes the lock and its own log, and moves the checkout to main.
child=0
if [[ -n ${LAB_TEST_PROVE_PARENT:-} && $LAB_TEST_PROVE_PARENT == "$PPID" && $action != prove ]]; then child=1; fi
unset LAB_TEST_PROVE_PARENT
if (( ! child )); then
  exec 9>"$work/state/lab-test.lock"
  flock -n 9 || { echo "lab-test: another lab-test run is going; try again when it ends" >&2; exit 1; }
  exec > >(tee "$logfile") 2>&1
fi
echo "lab-test: $action at $(date -u +%FT%TZ)"
mkdir -p "$files"
if (( ! child )); then
  [[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
  git -C "$repo" fetch --quiet origin main
  git -C "$repo" checkout --quiet --detach origin/main
fi
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
  node=$(node_name) || { echo "lab-test: refused, the node name could not be read"; return 1; }
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
  python3 -I - "$settings" "$iso_out" "$vars" "$(node_name)" <<'PY'
import hashlib, json, sys
s = json.load(open(sys.argv[1]))
h = hashlib.sha256()
with open(sys.argv[2], "rb") as f:
    for b in iter(lambda: f.read(1 << 20), b""):
        h.update(b)
json.dump({
    "proxmox_node_name": sys.argv[4], "vnet": "dev",
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
  px_api "nodes/$(node_name)/storage/local/content" | python3 -I -c 'import json, sys
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

# A command on the copy's VM 100 as root, over SSH by the key firstboot made for this copy, through the copy: VM 100's
# LAN is the copy's mgmt VLAN, which exists only inside the copy. Root's shell there is csh behind opnsense-shell, so
# a command must not use sh redirects. The key, its public line and VM 100's host key stay in $files/opnsense-ssh.*,
# and destroy removes them.
vm100_proxy() { echo "ssh -i $sshkey -o BatchMode=yes -o ConnectTimeout=10 -o UserKnownHostsFile=$files/known_hosts root@$addr -W %h:%p"; }
vm100_opts() { # sets the array o to the ssh options for VM 100
  o=(-i "$files/opnsense-ssh.key" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10
     -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$files/opnsense-ssh.known_hosts" -o ProxyCommand="$(vm100_proxy)")
}
vm100() {
  local _ gw o
  read -r _ gw _ < <(mgmt_values)
  vm100_opts
  ssh "${o[@]}" "root@$gw" "$@"
}

# Reads VM 100's `sshd -T` on stdin and names what is not as opnsense-ssh-key.php sets it: root by key, password and
# keyboard-interactive sign-in off, and sshd listening on the mgmt gateway (LAN) and loopback only, never WAN.
# OPNsense listens on every address of the chosen interfaces and lo0, link-local ones with their scope
# (openssh.inc, openssh_configure_do; interfaces.inc, interfaces_addresses), so a link-local address is let through
# unless its scope is the WAN device.
sshd_settings_ok() { # mgmt gateway, WAN device
  python3 -I -c 'import ipaddress, sys
gw, wan, got, bad = sys.argv[1], sys.argv[2], {}, []
for line in sys.stdin:
    k, _, v = line.strip().partition(" ")
    got.setdefault(k.lower(), []).append(v)
for k, want in (("permitrootlogin", "yes"), ("pubkeyauthentication", "yes"), ("passwordauthentication", "no"),
                ("kbdinteractiveauthentication", "no")):
    if got.get(k) != [want]:
        bad.append("%s is %s" % (k, " ".join(got.get(k, ["unset"]))))
def allowed(a):
    host = a.split(" ", 1)[0].rsplit(":", 1)[0].strip("[]")
    host, _, scope = host.partition("%")
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    return ip.is_loopback or (ip.is_link_local and scope not in ("", wan))
listen = got.get("listenaddress", [])
if gw + ":22" not in listen or any(a != gw + ":22" and not allowed(a) for a in listen):
    bad.append("listenaddress is " + (" ".join(listen) or "unset"))
if bad:
    print("; ".join(bad))
    sys.exit(1)' "$1" "$2"
}

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
  # VM 100's WAN bridge in the copy, with no ports (lab-test-answer.py, COPY_WAN_BRIDGE): the copy's vmbr0 is dev.
  vm 'n=$(hostname); pvesh get "/nodes/$n/network/vmbr9" >/dev/null 2>&1 || {
    pvesh create "/nodes/$n/network" --iface vmbr9 --type bridge --autostart 1 --comments "lab test copy: VM 100 WAN, no ports" &&
    pvesh set "/nodes/$n/network"; }'
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
# The whole lab range, the mgmt /24's /16 (STD-0002), as the copy's inventory has it.
lab_supernet() {
  "$py" -I -c 'import ipaddress, sys, yaml
v = [x for x in yaml.safe_load(open(sys.argv[1]))["lab_vlans"] if x["name"] == "mgmt"][0]
print(ipaddress.ip_network(v["cidr"]).supernet(new_prefix=16))' "$vlans"
}

# The mgmt VLAN's tag, its gateway (VM 100's LAN address) and its prefix length, from the VLAN file.
mgmt_values() {
  "$py" -I -c 'import ipaddress, sys, yaml
v = [x for x in yaml.safe_load(open(sys.argv[1]))["lab_vlans"] if x["name"] == "mgmt"][0]
n = ipaddress.ip_network(v["cidr"])
print(v["id"], n.network_address + 1, n.prefixlen)' "$vlans"
}

firstboot() {
  wait_ssh
  vm 'qm status 100' | grep -qx 'status: running' || { echo "lab-test: VM 100 is not running in the copy; run lab-test lab first"; return 1; }
  local tag gw prefix
  read -r tag gw prefix < <(mgmt_values)
  [[ -s $files/opnsense-root.pass ]] || openssl rand -base64 32 > "$files/opnsense-root.pass"
  openssl passwd -6 -stdin < "$files/opnsense-root.pass" > "$files/opnsense-root.hash"
  # Step 6's API user `ansible`: the key and secret stay on the box; OPNsense gets only "<key>|<hash of the secret>"
  # (hosts/ansible/bootstrap/opnsense-ansible-user.php). Over the console, so the copy needs no guest agent.
  [[ -s $files/opnsense-api.key ]] || openssl rand -hex 40 > "$files/opnsense-api.key"
  [[ -s $files/opnsense-api.secret ]] || openssl rand -hex 40 > "$files/opnsense-api.secret"
  printf '%s|%s\n' "$(cat "$files/opnsense-api.key")" "$(openssl passwd -6 -stdin < "$files/opnsense-api.secret")" \
    > "$files/opnsense-api.line"
  # SSH for root on VM 100, LAN only, so later steps can run commands there: the key is made here for this copy and
  # stays on the box; VM 100 gets only its public line (hosts/ansible/bootstrap/opnsense-ssh-key.php).
  if [[ ! -s $files/opnsense-ssh.key || ! -s $files/opnsense-ssh.key.pub ]]; then
    rm -f "$files/opnsense-ssh.key" "$files/opnsense-ssh.key.pub"
    ssh-keygen -q -t ed25519 -N "" -C lab-test-vm100 -f "$files/opnsense-ssh.key"
  fi
  # net0 is the trunk (vtnet0) and net1 is WAN (vtnet1), in firewall/main.tf's order.
  python3 -I -c 'import json, sys
print(json.dumps({
    "passwords": ["opnsense", open(sys.argv[1]).read().strip()], "dir": "/root/lab-test",
    "files": {"opnsense-first-boot.php": sys.argv[2], "root.hash": sys.argv[3],
              "opnsense-ansible-user.php": sys.argv[6], "ansible-apikey.line": sys.argv[7],
              "opnsense-ssh-key.php": sys.argv[8], "root-ssh.pub": sys.argv[9]},
    "commands": [
        "php opnsense-first-boot.php vtnet0 %s %s vtnet1 root.hash" % (sys.argv[4], sys.argv[5]),
        # The script reads /root/ansible-apikey.line; the line goes however the script ends.
        "cp ansible-apikey.line /root/ansible-apikey.line && chmod 600 /root/ansible-apikey.line"
        " && php opnsense-ansible-user.php; r=$?; rm -f /root/ansible-apikey.line ansible-apikey.line root.hash; (exit $r)",
        "php opnsense-ssh-key.php root-ssh.pub; r=$?; rm -f root-ssh.pub; (exit $r)"],
    "reboot": True}))' "$files/opnsense-root.pass" "$repo/hosts/ansible/bootstrap/opnsense-first-boot.php" \
    "$files/opnsense-root.hash" "$tag" "$gw/$prefix" "$repo/hosts/ansible/bootstrap/opnsense-ansible-user.php" \
    "$files/opnsense-api.line" "$repo/hosts/ansible/bootstrap/opnsense-ssh-key.php" "$files/opnsense-ssh.key.pub" \
    > "$files/console-plan.json"
  local rc=0
  python3 -I "$console_py" "$files/console-plan.json" ssh -i "$sshkey" -o BatchMode=yes -o ConnectTimeout=10 \
    -o UserKnownHostsFile="$files/known_hosts" "root@$addr" "socat UNIX-CONNECT:/var/run/qemu-server/100.serial0 STDIO" || rc=$?
  rm -f "$files/console-plan.json"
  (( rc == 0 )) || return "$rc"
  # The copy has mgmt .2 from lab; the default LAN rules let it ping the gateway.
  local _ up=0
  for _ in $(seq 1 60); do
    if vm "ping -c 1 -W 2 $gw >/dev/null"; then up=1; break; fi
    sleep 10
  done
  (( up )) || { echo "lab-test: the mgmt gateway $gw does not answer from the copy after 10 minutes"; return 1; }
  echo "lab-test: the mgmt gateway $gw answers from the copy"
  # The API user answers on one of its own paths (api/interfaces/vlan_settings, privilege page-interfaces-vlan-edit).
  # -k: OPNsense's own certificate is self-signed, and the mgmt VLAN exists only inside the copy (its vmbr1 has no
  # ports). The key and secret go to curl on stdin, never on a command line.
  up=0
  for _ in $(seq 1 30); do
    if printf 'user = "%s:%s"\n' "$(cat "$files/opnsense-api.key")" "$(cat "$files/opnsense-api.secret")" |
        vm "curl -sk --fail --max-time 10 -K - -o /dev/null https://$gw/api/interfaces/vlan_settings/search_item"; then
      up=1; break
    fi
    sleep 10
  done
  (( up )) || { echo "lab-test: the API user ansible gets no answer on https://$gw/api after 5 minutes"; return 1; }
  echo "lab-test: the API user ansible answers on https://$gw/api"
  # SSH by the copy's key: sshd's own view of its settings, read over that SSH.
  local sshd=""
  up=0
  for _ in $(seq 1 30); do
    if sshd=$(vm100 /usr/local/sbin/sshd -T); then up=1; break; fi
    sleep 10
  done
  (( up )) || { echo "lab-test: VM 100 does not answer SSH as root by the copy's key after 5 minutes"; return 1; }
  local problems
  problems=$(sshd_settings_ok "$gw" vtnet1 <<<"$sshd") \
    || { echo "lab-test: VM 100's sshd is not as opnsense-ssh-key.php sets it: $problems"; return 1; }
  echo "lab-test: VM 100 answers SSH as root by the copy's key, on $gw only, with password sign-in off"
}

# set-up-lab-network-and-firewall.md step 7 against the copy's VM 100: playbooks/opnsense.yml as the controller runs it,
# unchanged. The copy's mgmt VLAN exists only inside the copy (its vmbr1 has no ports), so the box reaches the API
# through an SSH tunnel to the copy, which has mgmt .2 (lab); the copy's inventory names the API localhost on the
# tunnel's port. The key and secret go to the playbook as extra vars from a file only this user reads, never on a
# command line. The DNS proof (tag dns_proof) runs dig on the controller against the gateway, which the box can't reach,
# so it is left out here.
opnsense() {
  wait_ssh
  [[ -s $files/opnsense-api.key && -s $files/opnsense-api.secret ]] || { echo "lab-test: the API key is not on the box; run lab-test firstboot first"; return 1; }
  [[ -s $files/opnsense-ssh.key ]] || { echo "lab-test: VM 100's SSH key is not on the box; run lab-test firstboot first"; return 1; }
  [[ -f $files/inventory/hosts.yml && -s $files/copy-ca.pem ]] || { echo "lab-test: run lab-test lab first"; return 1; }
  local tag gw prefix port tunnel n rc=0 _
  read -r tag gw prefix < <(mgmt_values)
  port=$("$py" -I -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
  "$py" -I "$answer_py" firewall-inventory "$settings" "$vlans" "$port" "$py" "$files/inventory/opnsense.yml"
  python3 -I -c 'import json, sys
print(json.dumps({"opnsense_api_key": open(sys.argv[1]).read().strip(),
                  "opnsense_api_secret": open(sys.argv[2]).read().strip()}))' \
    "$files/opnsense-api.key" "$files/opnsense-api.secret" > "$files/opnsense-api.vars.json"
  ssh -N -i "$sshkey" -o BatchMode=yes -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 \
    -o UserKnownHostsFile="$files/known_hosts" -L "127.0.0.1:$port:$gw:443" "root@$addr" &
  tunnel=$!
  # shellcheck disable=SC2064  # the tunnel's PID is known now
  trap "kill $tunnel 2>/dev/null; rm -f '$files/opnsense-api.vars.json'" EXIT
  for _ in $(seq 1 30); do
    "$py" -I -c 'import socket, sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=2).close()' "$port" 2>/dev/null && break
    kill -0 "$tunnel" 2>/dev/null || { echo "lab-test: the SSH tunnel to the copy ended"; return 1; }
    sleep 1
  done
  for n in 1 2; do
    echo "lab-test: opnsense.yml against the copy's VM 100, run $n"
    # oxlorg.opnsense sends every API call through HTTPS_PROXY when it is set, which can't reach the tunnel.
    ( cd "$repo/hosts/ansible"
      unset HTTPS_PROXY https_proxy
      ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home \
        ansible-playbook -i "$files/inventory" -e @"$files/opnsense-api.vars.json" playbooks/opnsense.yml \
        --skip-tags dns_proof ) 2>&1 | tee "$files/opnsense-run.log" || rc=$?
    (( rc == 0 )) || { echo "lab-test: opnsense.yml failed on run $n (exit $rc)"; return 1; }
  done
  grep -Eq '^opnsense_fw +: ok=[0-9]+ +changed=0 +unreachable=0 +failed=0' "$files/opnsense-run.log" \
    || { echo "lab-test: the second opnsense.yml run changed something; the role does not converge on the copy"; return 1; }
  echo "lab-test: opnsense.yml applied to the copy's VM 100; a second run shows changed=0"
  # The role's config must leave firstboot's SSH as it was: later steps run commands on VM 100 over it.
  local sshd problems
  sshd=$(vm100 /usr/local/sbin/sshd -T) \
    || { echo "lab-test: after opnsense.yml, VM 100 does not answer SSH as root by the copy's key"; return 1; }
  problems=$(sshd_settings_ok "$gw" vtnet1 <<<"$sshd") \
    || { echo "lab-test: after opnsense.yml, VM 100's sshd is not as opnsense-ssh-key.php sets it: $problems"; return 1; }
  echo "lab-test: after opnsense.yml, VM 100 still answers SSH as root by the copy's key, on $gw only"
}

# Sign-in through Keycloak on the copy's VM 100 (docs/runbooks/sign-in-to-opnsense-through-keycloak.md steps 1 to 3), the
# nano 26.1.6 image the lab firewall runs, set up by opnsense.yml. The plugin and Keycloak pins are opnsense-test's, read
# from opnsense-test.sh in this checkout, so the two proofs install the same bytes.
#  - The package: downloaded on the box, checked against its SHA-256, copied over firstboot's SSH, then `pkg add`.
#  - The settings: hosts/ansible/bootstrap/opnsense-oidc-server.php, with D-0037 rule 5's settings fixed in it, the
#    proof's CA, and a local admin for the test user; its settings file holds the client secret and goes however it ends.
#  - Keycloak: opnsense-test's realm at VM 100's GUI origin, https://<mgmt .1>, in a container on the box that listens
#    on loopback only. VM 100 reaches it at the same https://127.0.0.1:8443 through a reverse forward on the SSH to it,
#    so neither the copy nor the box's filter changes. VM 100's LAN is the copy's mgmt VLAN, which nothing outside
#    the copy reaches.
#  - The browser: opnsense-test-prove.py with the copy's SSH path and a tunnel to VM 100's GUI, keeping https://<mgmt .1>
#    as the origin, which the plugin accepts because it is VM 100's own address (RelyingParty::acceptedRedirectUri).
# Its items 2 to 7, 9 and 10 must pass; item 10 stops Keycloak, so root signs in by password with Keycloak down.
KC_NAME=lab-test-keycloak
signin() {
  wait_ssh
  [[ -s $files/opnsense-ssh.key && -s $files/opnsense-root.pass ]] || { echo "lab-test: VM 100's SSH key or root password is not on the box; run lab-test firstboot first"; return 1; }
  command -v podman >/dev/null && [[ -x $prove_py && -x $seed_py ]] || { echo "lab-test: podman or opnsense-test's helpers are not on the box; run the agent_box role"; return 1; }
  local pins=$repo/hosts/ansible/roles/agent_box/files/opnsense-test.sh url sha image version
  url=$(sed -n 's/^PLUGIN_URL=\(https:\/\/github\.com\/jpawlowski\/opnsense-openid-connect\/releases\/download\/[^ ]*\.pkg\)$/\1/p' "$pins")
  sha=$(sed -n 's/^PLUGIN_SHA256=\([0-9a-f]\{64\}\)$/\1/p' "$pins")
  image=$(sed -n 's/^KEYCLOAK_IMAGE=\(quay\.io\/keycloak\/keycloak@sha256:[0-9a-f]\{64\}\)$/\1/p' "$pins")
  [[ -n $url && -n $sha && -n $image ]] || { echo "lab-test: the plugin or Keycloak pin is missing from opnsense-test.sh"; return 1; }
  version=${url##*/os-openid-connect-}; version=${version%.pkg}
  local tag gw prefix s=$files/signin o port f _
  read -r tag gw prefix < <(mgmt_values)
  gui="" rev=""   # the tunnels' PIDs, global so the EXIT trap still sees them when this function has returned
  vm100_opts
  rm -rf "$s" && mkdir -p "$s"
  # shellcheck disable=SC2064  # the folder is known now; the tunnels' PIDs are read when the trap runs
  trap "kill \$gui \$rev 2>/dev/null; podman rm -f $KC_NAME >/dev/null 2>&1; rm -rf '$s'" EXIT

  curl -sS --fail --max-time 300 -L -o "$s/os-openid-connect.pkg.part" "$url"
  echo "$sha  $s/os-openid-connect.pkg.part" | sha256sum -c --quiet - \
    || { echo "lab-test: the os-openid-connect package does not match its pin $sha; nothing installed"; return 1; }
  mv "$s/os-openid-connect.pkg.part" "$s/os-openid-connect.pkg"
  echo "lab-test: signin: os-openid-connect $version matches sha256 $sha on the box"
  scp -q "${o[@]}" "$s/os-openid-connect.pkg" "$repo/hosts/ansible/bootstrap/opnsense-oidc-server.php" "root@$gw:/root/"
  vm100 'pkg add /root/os-openid-connect.pkg; set r = $status; rm -f /root/os-openid-connect.pkg; exit $r'
  [[ $(vm100 "pkg query '%n %v' os-openid-connect") == "os-openid-connect $version" ]] \
    || { echo "lab-test: os-openid-connect $version is not installed on VM 100"; return 1; }
  echo "lab-test: signin: os-openid-connect $version installed on VM 100 by pkg add"

  # The proof's secrets and CA, made for this run; Keycloak's certificate is for 127.0.0.1, where both sides reach it.
  for f in client.secret user.pass stranger.pass; do openssl rand -hex 24 > "$s/$f"; done
  cp "$files/opnsense-root.pass" "$s/root.pass"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj "/CN=lab-test signin proof CA" \
    -keyout "$s/ca.key" -out "$s/ca.pem" 2>/dev/null
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=127.0.0.1" -keyout "$s/kc.key" -out "$s/kc.csr" 2>/dev/null
  openssl x509 -req -in "$s/kc.csr" -CA "$s/ca.pem" -CAkey "$s/ca.key" -CAcreateserial -days 1 \
    -extfile <(printf 'subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n') -out "$s/kc.pem" 2>/dev/null
  rm -f "$s/ca.key" "$s/kc.csr"

  python3 -I -c 'import json, sys
s = sys.argv[1]
json.dump({"name": "keycloak-proof", "issuer": "https://127.0.0.1:8443/realms/opnsense-proof", "client_id": "opnsense",
           "client_secret": open(s + "/client.secret").read().strip(), "app_code": "keycloak",
           "ca": {"descr": "lab-test signin proof CA", "pem": open(s + "/ca.pem").read()}, "proof_admin": "proofadmin"},
          open(s + "/server.json", "w"))' "$s"
  scp -q "${o[@]}" "$s/server.json" "root@$gw:/root/lab-test-signin.json"
  rm -f "$s/server.json"
  local out
  out=$(vm100 'php /root/opnsense-oidc-server.php /root/lab-test-signin.json; set r = $status; rm -f /root/lab-test-signin.json /root/opnsense-oidc-server.php; exit $r') \
    || { echo "$out"; echo "lab-test: opnsense-oidc-server.php failed on VM 100"; return 1; }
  echo "$out"
  sed -n 's/^proof admin proofadmin uid \([0-9]\{4,\}\)$/\1/p' <<<"$out" > "$s/admin.uid"
  [[ -s $s/admin.uid ]] || { echo "lab-test: the settings script named no proof admin uid"; return 1; }

  "$py" -I "$seed_py" realm-at "https://$gw" "$s/realm.json"
  mkdir -p "$s/kc" "$s/kc-import"
  cp "$s/kc.pem" "$s/kc.key" "$s/kc/"
  cp "$s/realm.json" "$s/kc-import/"
  openssl rand -hex 24 > "$s/kc-admin.pass"
  podman rm -f "$KC_NAME" >/dev/null 2>&1 || true
  # As opnsense-test's: secrets by name from this command's environment, never in arguments or the realm file. Here
  # it listens on loopback only (http-host); nothing but the box and the reverse forward reach it.
  KC_BOOTSTRAP_ADMIN_PASSWORD=$(cat "$s/kc-admin.pass") KC_PROOF_CLIENT_SECRET=$(cat "$s/client.secret") \
  KC_PROOF_USER_PASS=$(cat "$s/user.pass") KC_PROOF_STRANGER_PASS=$(cat "$s/stranger.pass") \
    podman run -d --name "$KC_NAME" --network host \
    --userns=keep-id:uid=1000,gid=1000 -v "$s/kc:/opt/keycloak/conf/proof:ro,Z" -v "$s/kc-import:/opt/keycloak/data/import:ro,Z" \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=proof-admin -e KC_BOOTSTRAP_ADMIN_PASSWORD \
    -e KC_PROOF_CLIENT_SECRET -e KC_PROOF_USER_PASS -e KC_PROOF_STRANGER_PASS -e JAVA_OPTS_KC_HEAP="-Xms256m -Xmx1024m" \
    "$image" start --db=dev-file --cache=local --import-realm --http-enabled=false --http-host=127.0.0.1 --https-port=8443 \
    --https-certificate-file=/opt/keycloak/conf/proof/kc.pem --https-certificate-key-file=/opt/keycloak/conf/proof/kc.key \
    --hostname=https://127.0.0.1:8443 >/dev/null
  for _ in $(seq 1 60); do
    curl -sS --fail --max-time 5 --cacert "$s/ca.pem" https://127.0.0.1:8443/realms/opnsense-proof/.well-known/openid-configuration \
      -o "$s/discovery.json" 2>/dev/null && break
    sleep 5
  done
  [[ -s $s/discovery.json ]] || { echo "lab-test: the proof's Keycloak did not come up"; podman logs --tail 30 "$KC_NAME"; return 1; }
  "$py" -I -c 'import json, sys; sys.exit("ES256" not in json.load(open(sys.argv[1])).get("dpop_signing_alg_values_supported", []))' \
    "$s/discovery.json" || { echo "lab-test: stopped, Keycloak does not advertise DPoP with ES256"; return 1; }
  local pids lines
  pids=$(podman top "$KC_NAME" hpid | tail -n +2 | tr -s ' \n' '|' | sed 's/^|//; s/|$//')
  [[ -n $pids ]] || { echo "lab-test: the Keycloak container's processes could not be read"; return 1; }
  lines=$(ss -Hlntup | grep -E "pid=($pids),")
  if awk '$5 !~ /^(127\.|\[::1\]:|\[::ffff:127\.)/' <<<"$lines" | grep -q .; then
    echo "lab-test: stopped, the proof's Keycloak listens beyond loopback:"; awk '{print $1, $5}' <<<"$lines"; return 1
  fi
  awk '$1 == "tcp" && $5 == "127.0.0.1:8443"' <<<"$lines" | grep -q . || { echo "lab-test: the proof's Keycloak is not on 127.0.0.1:8443"; return 1; }
  echo "lab-test: signin: Keycloak (realm opnsense-proof, DPoP on) listens on loopback only, at https://127.0.0.1:8443"

  ssh -N "${o[@]}" -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -R 127.0.0.1:8443:127.0.0.1:8443 "root@$gw" &
  rev=$!
  port=$("$py" -I -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
  ssh -N -i "$sshkey" -o BatchMode=yes -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 \
    -o UserKnownHostsFile="$files/known_hosts" -L "127.0.0.1:$port:$gw:443" "root@$addr" &
  gui=$!
  local up=0
  for _ in $(seq 1 12); do
    kill -0 "$rev" 2>/dev/null && kill -0 "$gui" 2>/dev/null || { echo "lab-test: the reverse forward or the GUI tunnel ended"; return 1; }
    if vm100 'fetch -q -T 10 -o /dev/null https://127.0.0.1:8443/realms/opnsense-proof/.well-known/openid-configuration'; then up=1; break; fi
    sleep 5
  done
  (( up )) || { echo "lab-test: VM 100 does not reach the proof's Keycloak over verified https through the forward"; return 1; }
  echo "lab-test: signin: VM 100 reaches Keycloak at https://127.0.0.1:8443 through the forward, trusting the proof CA"
  vm100 'cat /usr/local/etc/lighttpd_webgui/cert.pem' > "$s/gui.pem"
  "$py" -I "$prove_py" "$gw" "$s" "$files/opnsense-ssh.key" "$files/opnsense-ssh.known_hosts" "$KC_NAME" "$(vm100_proxy)" "$port"
  echo "lab-test: signin: proof items 2 to 7, 9 and 10 passed on VM 100 (nano 26.1.6, os-openid-connect $version)"
}

# set-up-lab-network-and-firewall.md step 7's WAN safety check against the copy's VM 100, whose WAN is on the copy's
# portless vmbr9 (lab). 1: before link-up, over the console, WAN is a DHCP client and nothing else: dhclient on vtnet1,
# no radvd, Kea or dhcp6c. 2: link-up while lab-test-wan-watch.py watches vmbr9 on the copy, asking for a server every
# 5 seconds. 3: the same watch over a reboot of VM 100. Any server-type frame from the WAN's MAC, or none at all, takes
# WAN link-down again and stops. WAN stays up when all three pass; lab, run again, takes it down.
wancheck() {
  wait_ssh
  [[ -s $files/opnsense-root.pass && -s $files/state/firewall.tfvars.json ]] || { echo "lab-test: run lab-test firstboot first"; return 1; }
  local wanmac rc=0 watcher
  wanmac=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["opnsense_wan_mac"])' "$files/state/firewall.tfvars.json")
  python3 -I -c 'import json, sys
print(json.dumps({"passwords": [open(sys.argv[1]).read().strip()], "dir": "/root/lab-test", "files": {},
    "commands": ["pgrep -lf \"dhclient.*vtnet1\"", "! pgrep -lf \"radvd|kea-dhcp|dhcp6c\""], "reboot": False}))' \
    "$files/opnsense-root.pass" > "$files/console-plan.json"
  python3 -I "$console_py" "$files/console-plan.json" ssh -i "$sshkey" -o BatchMode=yes -o ConnectTimeout=10 \
    -o UserKnownHostsFile="$files/known_hosts" "root@$addr" "socat UNIX-CONNECT:/var/run/qemu-server/100.serial0 STDIO" || rc=$?
  rm -f "$files/console-plan.json"
  (( rc == 0 )) || { echo "lab-test: before link-up, WAN is not a DHCP client only; WAN stays down"; return 1; }
  wan_link() { # true|false
    python3 -I -c 'import json, sys
p = sys.argv[1]; v = json.load(open(p)); v["opnsense_wan_connected"] = sys.argv[2] == "true"
json.dump(v, open(p, "w"), indent=2)' "$files/state/firewall.tfvars.json" "$1"
    lab_folder firewall
  }
  wan_watch() { # seconds [port]; the watch's verdict is its exit code
    vm "python3 -I - vmbr9 $wanmac $*" < "$wan_watch_py"
  }
  echo "lab-test: WAN link-up with the watch on vmbr9"
  wan_watch 120 & watcher=$!
  sleep 5
  wan_link true
  wait "$watcher" || { echo "lab-test: the WAN check failed at link-up; WAN goes down"; wan_link false; return 1; }
  echo "lab-test: VM 100 reboots with the watch on vmbr9"
  # Over the reboot only frames from VM 100's new WAN tap count: net1 is tap100i1 (no NIC firewall in
  # firewall/main.tf), and a new QEMU process gives it a new interface index.
  wan_watch 240 tap100i1 & watcher=$!
  sleep 5
  vm 'qm reboot 100'
  wait "$watcher" || { echo "lab-test: the WAN check failed over the reboot; WAN goes down"; wan_link false; return 1; }
  echo "lab-test: the WAN check passed at link-up and over a reboot; WAN stays up on the copy's vmbr9"
}

# CT 900 in the copy, as set-up-tailnet-client-in-ct-900.md steps 1 to 3 and set-up-lab-dns.md's
# playbooks/tailnet-connector.yml do it on a fresh real host, but never joined: steps 4 and 5 (the key and the join)
# are a tailnet change, and the copy has no key. The client from the vendor's Debian repository, IP forwarding, the
# route unit and the advertised routes, which the client keeps as preferences until a login it never gets. Stops if
# CT 900 is ever logged in.
connector_state() { # CT 900's tailnet client state, or "none" before it is installed
  vm 'pct exec 900 -- tailscale status --json 2>/dev/null || true' |
    python3 -I -c 'import json, sys
try:
    print(json.load(sys.stdin).get("BackendState") or "none")
except ValueError:
    print("none")'
}

connector() {
  wait_ssh
  vm 'pct status 900' | grep -qx 'status: running' || { echo "lab-test: CT 900 is not running in the copy; run lab-test lab first"; return 1; }
  [[ -f $files/inventory/hosts.yml ]] || { echo "lab-test: run lab-test host first"; return 1; }
  local state tag gw prefix n rc=0
  state=$(connector_state)
  [[ $state != Running && $state != Starting ]] || { echo "lab-test: CT 900 is logged in to a tailnet ($state); the copy must never join. Stopped"; return 1; }
  read -r tag gw prefix < <(mgmt_values)
  # The runbook's own lines, steps 1 to 3, in CT 900 through the copy's pct.
  vm 'bash -s' <<'SH'
set -eu
pct exec 900 -- bash -c 'apt-get update && apt-get install -y curl ca-certificates'
pct exec 900 -- bash -c 'mkdir -p --mode=0755 /usr/share/keyrings &&
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg &&
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list'
pct exec 900 -- bash -c 'apt-get update && apt-get install -y tailscale'
[ "$(pct exec 900 -- systemctl is-enabled tailscaled)" = enabled ]
pct exec 900 -- bash -c 'printf "net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n" > /etc/sysctl.d/99-tailscale.conf && sysctl -p /etc/sysctl.d/99-tailscale.conf'
SH
  for n in 1 2; do
    echo "lab-test: tailnet-connector.yml against the copy, run $n"
    ( cd "$repo/hosts/ansible"
      ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home \
        ansible-playbook -i "$files/inventory" playbooks/tailnet-connector.yml ) 2>&1 | tee "$files/connector-run.log" || rc=$?
    (( rc == 0 )) || { echo "lab-test: tailnet-connector.yml failed on run $n (exit $rc)"; return 1; }
  done
  grep -Eq '^proxmox_host +: ok=[0-9]+ +changed=0 +unreachable=0 +failed=0' "$files/connector-run.log" \
    || { echo "lab-test: the second tailnet-connector.yml run changed something"; return 1; }
  # The route unit is up, the lab range goes through the copy's firewall on eth1, and the gateway answers there.
  vm "pct exec 900 -- systemctl is-active central-hub-lab-route.service &&
    pct exec 900 -- ip route show $(lab_supernet) | grep -q 'via $gw dev eth1' &&
    pct exec 900 -- ping -c 1 -W 2 -I eth1 $gw >/dev/null" \
    || { echo "lab-test: CT 900's route to the lab or the mgmt gateway $gw does not work"; return 1; }
  state=$(connector_state)
  [[ $state == NeedsLogin ]] || { echo "lab-test: CT 900's tailnet client is $state, not NeedsLogin"; return 1; }
  echo "lab-test: CT 900 has the tailnet client, forwarding, the lab route and its routes advertised, and never joined"
}

# set-up-lab-network-and-firewall.md step 8's host firewall against the copy: playbooks/proxmox-safety.yml --tags
# firewall, first with the switch off (rules written, ruleset shown), then on, as the runbook runs it. The second run
# arms the dead-man timer, proves every way in, and cancels the timer; a third run must change nothing. The copy's
# "home LAN" in its management IPSet is dev, where the box is (inventory). Notifications and backups are left out:
# their inputs are the owner's ntfy topic and a backup disk, which the copy does not have.
safety() {
  wait_ssh
  [[ -f $files/inventory/hosts.yml ]] || { echo "lab-test: run lab-test host first"; return 1; }
  local n rc=0 extra
  for n in 1 2 3; do
    extra=(); (( n == 1 )) || extra=(-e '{"proxmox_firewall_enable": true}')
    echo "lab-test: proxmox-safety.yml --tags firewall against the copy, run $n"
    ( cd "$repo/hosts/ansible"
      ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home \
        ansible-playbook -i "$files/inventory" playbooks/proxmox-safety.yml --tags firewall "${extra[@]}" ) 2>&1 \
      | tee "$files/safety-run.log" || rc=$?
    (( rc == 0 )) || { echo "lab-test: proxmox-safety.yml failed on run $n (exit $rc)"; return 1; }
  done
  grep -Eq '^proxmox_host +: ok=[0-9]+ +changed=0 +unreachable=0 +failed=0' "$files/safety-run.log" \
    || { echo "lab-test: the third proxmox-safety.yml run changed something"; return 1; }
  vm 'pve-firewall status' | grep -q 'enabled/running' || { echo "lab-test: the copy's firewall is not enabled and running"; return 1; }
  ! vm 'systemctl is-active --quiet central-hub-fw-deadman.timer' \
    || { echo "lab-test: the dead-man timer is still armed in the copy"; return 1; }
  echo "lab-test: the copy's host firewall is on, every way in still works, and the dead-man timer is cancelled"
}

# The whole copy, build to destroy, with no hand step (docs/specs/2026-11-lab-test-copy.md, "Two clean runs"): each
# step as its own run of this wrapper, so each keeps its own stop-on-error, under this run's lock, log and checkout.
# Destroy runs whether the steps pass or not, so dev can come back; the log says where a run stopped.
prove() {
  local step failed="" rc
  for step in plan apply check host lab firstboot opnsense signin wancheck connector safety; do
    echo "lab-test: prove: $step"
    rc=0; LAB_TEST_PROVE_PARENT=$$ "$0" "$step" || rc=$?
    (( rc == 0 )) || { failed=$step; echo "lab-test: prove: $step failed (exit $rc)"; break; }
  done
  echo "lab-test: prove: destroy"
  rc=0; LAB_TEST_PROVE_PARENT=$$ "$0" destroy || rc=$?
  (( rc == 0 )) || { echo "lab-test: prove: destroy failed (exit $rc); VM $VMID may still exist"; return 1; }
  [[ -z $failed ]] || { echo "lab-test: prove: stopped at $failed; the copy is destroyed"; return 1; }
  echo "lab-test: prove: every step passed, build to destroy, with no hand step"
}

case $action in
  plan) guards; tofu_run ;;
  apply) guards; tofu_run ;;
  check) check ;;
  host) host ;;
  lab) lab ;;
  firstboot) firstboot ;;
  opnsense) opnsense ;;
  signin) signin ;;
  wancheck) wancheck ;;
  connector) connector ;;
  safety) safety ;;
  prove) prove ;;
  destroy)
    podman rm -f "$KC_NAME" >/dev/null 2>&1 || true   # signin's Keycloak, if a run ended without its trap
    tofu_run
    # The copy's token, inventory and run folder states go with it; a new copy gets new ones. Root's password stays
    # with its hash, which the cached prepared ISO holds.
    rm -rf "$files/known_hosts" "$files"/*.part "$files/copy-token" "$files/inventory" "$files/state" "$files/copy-ca.pem" \
      "$files"/opnsense-root.* "$files"/opnsense-api.* "$files"/opnsense-ssh.* "$files/opnsense-run.log" "$files/signin" \
      "$files/connector-run.log" "$files/safety-run.log"
    echo "lab-test: VM $VMID destroyed"
    leftovers
    ;;
esac
