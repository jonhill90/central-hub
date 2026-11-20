#!/bin/bash
# /usr/local/libexec/agent-box/desktop.sh: build and set up the owner's desktop VM
# (docs/runbooks/set-up-the-desktop.md). It runs as user `keys` through sudo, so the session that
# asks for it never sees the Proxmox token or the VM's SSH key. Installed by the agent_box role;
# root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/desktop.sh plan|apply|configure|destroy
#   sudo -n -u keys /usr/local/libexec/agent-box/desktop.sh configure-test|start|stop|status|rdp-check|diag
# configure-test is configure for a VM that is a test build: the box makes two random passwords (login and
# RDP, kept in the keys folder, never printed), the role sets them without the console and lets RDP in from
# the box's own address too, so rdp-check can prove the RDP service from the box. The owner's own desktop is a
# rebuild with plain configure afterwards (the owner types the passwords at the console). start and status
# read and power VM 400 with the dev token (VM.Audit, VM.PowerMgmt); rdp-check speaks RDP to the VM's port 3389.
# plan, apply, destroy: OpenTofu on hosts/terraform/home/desktop with the agents' Proxmox token.
# configure: the desktop playbook over SSH as the cloud-init admin user. The role removes that
# user's key at the end of its run, so a second configure on the same VM can't log in: a change is a
# destroy and a rebuild. The owner's password is never handled here: the owner types it at the
# Proxmox console, so it passes through no agent, file or log.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | configure | destroy | configure-test | start | stop | status | rdp-check | diag) action=$1 ;;
  *) echo "usage: desktop plan|apply|configure|destroy|configure-test|start|stop|status|rdp-check|diag" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
repo=$work/checkouts/desktop   # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/desktop
settings=$work/desktop.json   # private values the agent_box role writes from the inventory
state=$work/state/desktop.tfstate
plan=$work/state/desktop.tfplan
vars=$work/state/desktop.tfvars.json
sshkey=$keys/desktop-ssh
# c1's lab intermediate with the root appended, the same file the prod rebuild hands to k8s_certs and
# k8s_node_trust. configure puts its root in the desktop's trust store (role k8s_node_trust).
labchain=$keys/prod/lab-ca/c1-intermediate-chain.crt
prodinv=$keys/prod/inventory-hosts.yml   # the controller's prod inventory; configure reads the zone from it
# Ansible comes from the box's own virtual environment (role agent_box), as in the rebuild wrapper.
export HOME=$work PATH=/usr/local/libexec/agent-box/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/desktop TF_IN_AUTOMATION=1 ANSIBLE_COLLECTIONS_PATH=/usr/local/libexec/agent-box/collections ANSIBLE_HOME=$work/ansible-home

[[ -f $settings ]] || { echo "desktop: $settings is missing; set agent_box_desktop in the inventory and run the agent_box role" >&2; exit 1; }

# Only reviewed code on main runs with the keys, never a checkout a session can edit.
# One desktop run at a time, in its own checkout: no other run, of this wrapper or another, can
# move the code under it. The lock is held until the run and everything it starts end.
exec 9>"$work/state/desktop.lock"
flock -n 9 || { echo "desktop: another desktop run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "desktop: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# The VM's own SSH key, made here the first time. Only its public half leaves this folder.
[[ -f $sshkey ]] || ssh-keygen -q -t ed25519 -N "" -C "keys@agent-box desktop" -f "$sshkey"

# The destroyed VM's host key. Its rebuild comes up at the same address with a new key, which configure's
# strict checking refuses ("REMOTE HOST IDENTIFICATION HAS CHANGED", desktop rebuild of 2026-11-19), and
# only this wrapper can write keys' known_hosts. So a destroy that ran drops that address's line, and the
# next configure meets the new VM's key fresh (accept-new).
forget_host_key() {
  local address known=$work/.ssh/known_hosts
  address=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["address"])' "$settings")
  [[ -f $known ]] || return 0
  ssh-keygen -R "$address" -f "$known" >/dev/null 2>&1 || true
  rm -f "$known.old"
  echo "desktop: the destroyed VM's host key is forgotten"
}

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
    "desktop": {k: s[k] for k in ("name", "vm_id", "address", "cores", "memory_mb", "disk_gb")},
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
      [[ -f $plan ]] || { echo "desktop: no saved plan; run desktop plan first" >&2; exit 1; }
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
    destroy)
      tofu plan -destroy -input=false -var-file="$vars" -out="$plan"
      tofu apply -input=false "$plan"
      rm -f "$plan"
      forget_host_key
      rm -f "$keys/desktop-test-login"
      echo "desktop: the test login file is deleted"
      ;;
  esac
}

configure() {
  local extra inventory
  extra=$(mktemp --suffix=.json "$work/state/desktop-extra.XXXXXX")
  # The .json suffix makes Ansible read the inventory as YAML (JSON), not INI.
  inventory=$(mktemp --suffix=.json "$work/state/desktop-inventory.XXXXXX")
  # Expanded now: the trap runs after configure returns, when its locals are gone.
  # shellcheck disable=SC2064
  trap "rm -f '$extra' '$inventory'" EXIT
  # Without the lab root the desktop's browser warns on every lab name, so configure stops instead.
  [[ -s $labchain ]] || { echo "desktop: $labchain is missing; the desktop would not trust the lab's names (install the prod keys first)" >&2; exit 1; }
  # The lab's zone, for the role's trust check: it opens https://<app>.<zone>/ from the VM before the admin key goes.
  # Read from the prod inventory the controller's prod-files run copies here (c1-ansible reads the same file), so no
  # new private value is needed. Never printed.
  [[ -s $prodinv ]] || { echo "desktop: $prodinv is missing; the desktop's check of the apps' names needs the lab's zone (install the prod keys first)" >&2; exit 1; }
  python3 -I - "$settings" "$inventory" "$extra" "$labchain" "$prodinv" "${test_login:-}" "$keys/desktop-test-login" <<'PY'
import json, os, sys, yaml
s = json.load(open(sys.argv[1]))
admin = s.get("admin_user", "admin")
zones = set()
def walk(n):
    if isinstance(n, dict):
        for k, v in n.items():
            if k == "k8s_gateway_zone" and isinstance(v, str) and v.strip():
                zones.add(v.strip())
            else:
                walk(v)
    elif isinstance(n, list):
        for i in n:
            walk(i)
walk(yaml.safe_load(open(sys.argv[5])))
if len(zones) != 1 or "{" in next(iter(zones)) or "/" in next(iter(zones)):
    sys.exit("desktop: the prod inventory must set k8s_gateway_zone to one plain zone (found %d values)" % len(zones))
json.dump({"desktop": {"hosts": {"desktop_vm": {
    "ansible_host": s["address"], "ansible_user": admin}}}}, open(sys.argv[2], "w"))
json.dump({"desktop_rdp_source": s["rdp_source"], "desktop_admin_user": admin,
           "k8s_node_trust_enabled": True, "k8s_node_trust_chain_file": sys.argv[4],
           "desktop_trust_check_zone": zones.pop()},
          open(sys.argv[3], "w"))
if sys.argv[6]:
    # A test build: two random passwords, kept in the keys folder (0600, the keys user's) and never printed.
    import secrets, socket
    login, rdp = secrets.token_urlsafe(24), secrets.token_urlsafe(24)
    fd = os.open(sys.argv[7], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"login_password": login, "rdp_password": rdp}, f)
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.connect((s["address"], 3389))
    extra = json.load(open(sys.argv[3]))
    extra.update({"desktop_test_login": True, "desktop_test_login_password": login,
                  "desktop_test_rdp_password": rdp, "desktop_lock_admin": False,
                  "desktop_rdp_extra_sources": [u.getsockname()[0] + "/32"]})
    fd = os.open(sys.argv[3], os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(extra, f)
PY
  # A plain configure is the owner's build: the test passwords of an earlier test build are not kept.
  [[ -n ${test_login:-} ]] || { rm -f "$keys/desktop-test-login"; echo "desktop: the test login file is deleted"; }
  mkdir -p "$work/.ssh"
  cd "$repo/hosts/ansible"
  # A rebuilt VM has a new host key: `desktop destroy` drops the old one (forget_host_key), so the
  # first configure after a rebuild accepts the new key, and any later key change stops the run.
  ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/.ssh/known_hosts" \
    ansible-playbook -i "$inventory" --private-key "$sshkey" -e "@$extra" playbooks/desktop.yml
}

# One call to the Proxmox API with the dev token (header on stdin, never in curl's arguments).
px_api() { # method path
  (set -a; . "$keys/proxmox-dev.env"; set +a
    insecure=(); case "${PROXMOX_VE_INSECURE:-}" in true|1) insecure=(-k) ;; esac
    printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
      curl -sS --fail --max-time 30 "${insecure[@]}" -K - -X "$1" "${PROXMOX_VE_ENDPOINT%/}/api2/json/$2")
}
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

vm_power() { # status|start
  local node vmid cur free need
  node=$(setting proxmox_node_name); vmid=$(setting vm_id)
  cur=$(px_api GET "nodes/$node/qemu/$vmid/status/current" | python3 -I -c 'import json,sys; d=json.load(sys.stdin)["data"]; print(d["status"], d.get("maxmem",0)//1048576)')
  echo "desktop: VM $vmid is ${cur% *} (memory ${cur#* } MiB)"
  if [[ $1 == stop ]]; then
    [[ ${cur% *} == running ]] || return 0
    px_api POST "nodes/$node/qemu/$vmid/status/shutdown" >/dev/null && echo "desktop: shutdown requested, the VM's memory is freed once it stops"
    return 0
  fi
  [[ $1 == start && ${cur% *} != running ]] || return 0
  need=$(( ${cur#* } + 512 ))
  free=$(px_api GET "nodes/$node/status" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["data"]["memory"]["available"]//1048576)')
  (( free >= need )) || { echo "desktop: not started, the node has $free MiB available and the VM needs $need MiB" >&2; exit 1; }
  px_api POST "nodes/$node/qemu/$vmid/status/start" >/dev/null && echo "desktop: start requested ($free MiB available)"
}

# Speaks RDP to the VM's port 3389 and prints what answers: the X.224 negotiation (the protocol the server
# picks), then the TLS handshake and the certificate's subject. It sends no password, so it proves the remote
# desktop service answers from this box, not that a login works.
rdp_check() {
  python3 -I - "$(setting address)" <<'PY'
import socket, ssl, struct, sys
host = sys.argv[1]
req = b"Cookie: mstshash=probe\r\n"
neg = struct.pack("<BBHI", 1, 0, 8, 3)   # RDP_NEG_REQ: TLS (1) and CredSSP/NLA (2)
x224 = bytes([6 + len(req) + len(neg), 0xE0, 0, 0, 0, 0, 0]) + req + neg
pkt = struct.pack(">BBH", 3, 0, 4 + len(x224)) + x224
try:
    s = socket.create_connection((host, 3389), timeout=10)
except OSError as e:
    sys.exit("desktop rdp-check: port 3389 did not answer: %s" % e)
s.sendall(pkt)
r = s.recv(512)
if len(r) < 19 or r[5] != 0xD0 or r[11] != 2:
    sys.exit("desktop rdp-check: not an RDP connection confirm: %r" % r[:32])
proto = struct.unpack("<I", r[15:19])[0]
names = {1: "TLS", 2: "CredSSP (NLA)", 3: "TLS and CredSSP"}
print("desktop rdp-check: X.224 connection confirm, the server picked %s" % names.get(proto, proto))
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
t = ctx.wrap_socket(s)
der = t.getpeercert(True)
print("desktop rdp-check: TLS handshake done (%s), certificate %d bytes" % (t.version(), len(der)))
print("desktop rdp-check: RDP service answers; no login was tried")
PY
}

# Read-only look inside a TEST build: configure-test leaves the admin key and ssh in place (the test VM is
# destroyed after the check, and the owner's build is a plain configure that removes both). Runs fixed commands only.
diag() {
  [[ -f $keys/desktop-test-login ]] || { echo "desktop diag: only for a test build (no test login file: this VM is the owner's build)" >&2; exit 1; }
  ssh -n -i "$sshkey" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$work/.ssh/known_hosts" -o BatchMode=yes -o ConnectTimeout=15 \
    "$(python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s.get("admin_user","admin")+"@"+s["address"])' "$settings")" \
    'systemctl is-active gnome-remote-desktop.service desktop-rdp.path gdm.service firewalld; sudo -n systemctl status gnome-remote-desktop.service --no-pager -l | head -30; sudo -n journalctl -u gnome-remote-desktop -u desktop-rdp.path -b --no-pager | tail -40; echo listening ports:; ss -ltnH | awk "{print \$4}" | sed "s/.*://"; sudo -n ls -l /var/lib/desktop/ /etc/gnome-remote-desktop/ /var/lib/gnome-remote-desktop/ 2>&1 | head -30; sudo -n firewall-cmd --list-all' 2>&1 |
    sed -E 's/[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]+)?/<ipv4>/g'   # no address is printed (lab-token's rule)
}

case $action in
  diag) mkdir -p "$work/.ssh"; diag ;;
  configure) configure ;;
  configure-test) test_login=1 configure ;;
  status | start | stop) vm_power "$action" ;;
  rdp-check) rdp_check ;;
  *) tofu_run ;;
esac
