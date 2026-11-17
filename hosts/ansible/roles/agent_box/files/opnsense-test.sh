#!/bin/bash
# /usr/local/libexec/agent-box/opnsense-test.sh: a throwaway OPNsense 26.1 on dev, VM 257, to prove sign-in
# through Keycloak with os-openid-connect before VM 100 gets it (docs/runbooks/prove-opnsense-sign-in-on-dev.md).
# It runs as user `keys` through sudo, so the session that asks for it never sees the Proxmox token or the
# proof's keys and passwords. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/opnsense-test.sh plan|apply|configure|prove|destroy|log
# plan, apply: download and check the FreeBSD 14.3 cloud image, build the seed ISO, then OpenTofu on
#   hosts/terraform/home/opnsense-test with the agents' Proxmox token. Refused while dev has any VM.
# configure: over SSH as root, check the release, measure dev's reach to the mirrors, seed /conf/config.xml,
#   run the pinned opnsense-bootstrap, then pkg add the pinned os-openid-connect package.
# prove: start the proof's Keycloak on this box, run proof items 2 to 7 and 9, stop Keycloak, remove its data.
# destroy: tofu destroy (proof item 8), the Keycloak container if still there, and the proof folder.
# log: the last run's log.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | configure | prove | destroy | log) action=$1 ;;
  *) echo "usage: opnsense-test plan|apply|configure|prove|destroy|log" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
repo=$work/checkouts/opnsense-test   # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/opnsense-test
settings=$work/opnsense-test.json    # private values the agent_box role writes from the inventory
state=$work/state/opnsense-test.tfstate
plan=$work/state/opnsense-test.tfplan
vars=$work/state/opnsense-test.tfvars.json
files=$work/opnsense-test            # image, seed ISO, proof folder; removed by destroy, except the image
proof=$files/proof
sshkey=$keys/opnsense-test-ssh
logfile=$work/state/opnsense-test.log
export HOME=$work PATH=/usr/local/libexec/agent-box/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin
export TF_DATA_DIR=$work/tofu-data/opnsense-test TF_IN_AUTOMATION=1
py=/usr/local/libexec/agent-box/ansible-venv/bin/python3   # has PyYAML, for the shared VLAN file
seed_py=$libexec/opnsense-test-seed.py

VMID=257
# The FreeBSD release OPNsense 26.1 is built on (14.3-RELEASE-p1). The 14.3 images now sit in the archive,
# over plain http, so the pinned sha256 of the archive's CHECKSUM.SHA256 line is the only integrity check.
IMAGE_XZ=FreeBSD-14.3-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz
IMAGE_URL=http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/VM-IMAGES/14.3-RELEASE/amd64/Latest/$IMAGE_XZ
IMAGE_SHA256=002e4ba15a5af021f9765f85c19e03edae396ea83306671a7484659d5fd9da69
# opnsense/update at tag 26.1, commit 7221e9bf306acc503ea556e1e488d99b59e8152b: the raw .sh.in, whose own
# FreeBSD release check is skipped because FREEBSD stays a placeholder (line 33; the check, lines 125-128).
BOOTSTRAP_URL=https://raw.githubusercontent.com/opnsense/update/7221e9bf306acc503ea556e1e488d99b59e8152b/src/bootstrap/opnsense-bootstrap.sh.in
BOOTSTRAP_SHA256=0289fb42845edfc4e4b5f29de5e3510f20065d4073f5c0c892cb698169f1e9c4
# os-openid-connect v1.0.0-beta5 (commit e7f5f7b3ed0dc6d71463bd7cbc08d65cbc794e12). CI's plugin-pin job runs
# `gh attestation verify` on this exact file and digest; here the box checks the digest before it leaves.
PLUGIN_URL=https://github.com/jpawlowski/opnsense-openid-connect/releases/download/v1.0.0-beta5/os-openid-connect-1.0.0.beta5.pkg
PLUGIN_SHA256=4b222b0de4ff9523cf3c86b23e984507e21c9a92a02bafe7cc01e406a41b117c
# Keycloak 26.8.1, the release c1 runs, by the digest .github/hosts-check/identity/test_realm.sh pins.
KEYCLOAK_IMAGE=quay.io/keycloak/keycloak@sha256:a78d6b79572168cb25886b80a8b5b8d4ed4390743e3eecb810538683e209dd6b
KC_NAME=opnsense-test-keycloak

[[ $action == log ]] && { cat "$logfile" 2>/dev/null || echo "opnsense-test: no log yet"; exit 0; }
[[ -f $settings ]] || { echo "opnsense-test: $settings is missing; set agent_box_opnsense_test in the inventory and run the agent_box role" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

exec 9>"$work/state/opnsense-test.lock"
flock -n 9 || { echo "opnsense-test: another opnsense-test run is going; try again when it ends" >&2; exit 1; }
exec > >(tee "$logfile") 2>&1
echo "opnsense-test: $action at $(date -u +%FT%TZ)"
mkdir -p "$files"
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "opnsense-test: central-hub $(git -C "$repo" rev-parse --short HEAD)"
vlans=$repo/hosts/ansible/inventories/home/group_vars/all/vlans.yml
[[ -f $sshkey ]] || ssh-keygen -q -t ed25519 -N "" -C "keys@agent-box opnsense-test" -f "$sshkey"
addr=$(setting address)
kc_addr=$(setting keycloak_address)

# One Proxmox API call with the agents' token, as the dev rebuild makes them; the token goes to curl on stdin.
px_api() { # path
  # shellcheck source=/dev/null
  ( set -a; . "$keys/proxmox-dev.env"; set +a
    insecure=(); case "${PROXMOX_VE_INSECURE:-}" in true|1) insecure=(-k) ;; esac
    printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
      curl -sS --fail --max-time 30 "${insecure[@]}" -K - "${PROXMOX_VE_ENDPOINT%/}/api2/json/$1" )
}

# Dev and the test VM never run together: dev's state must hold no resource, dev's tfvars must not
# declare VM 257, no dev rebuild may be running, and the node must have the VM's memory plus the margin.
guards() {
  local n
  if [[ -s $work/state/dev-vms.tfstate ]]; then
    n=$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("resources", [])))' "$work/state/dev-vms.tfstate")
    [[ $n == 0 ]] || { echo "opnsense-test: refused, dev's state holds $n resources; tear dev down first (rebuild teardown)"; return 1; }
  fi
  if grep -Eq "(vm_id|vmid)[[:space:]]*=[[:space:]]*$VMID([^0-9]|$)" "$keys/dev-vms.tfvars" 2>/dev/null; then
    echo "opnsense-test: refused, dev-vms.tfvars declares VM $VMID"; return 1
  fi
  exec 8>"$work/state/rebuild.lock"
  flock -n 8 || { echo "opnsense-test: refused, a dev rebuild run is going"; return 1; }
  local node free need
  node=$(setting proxmox_node_name)
  need=$(( $(setting memory_mb) + 2048 ))
  free=$(px_api "nodes/$node/status" | python3 -I -c 'import json,sys
m = json.load(sys.stdin)["data"]["memory"]
print((m["available"] if m.get("available") is not None else m["total"] - m["used"]) // 1048576)') \
    || { echo "opnsense-test: refused, the node's free memory could not be read"; return 1; }
  echo "opnsense-test: preflight: node free memory $free MiB, need $need MiB (the VM plus the 2048 MiB margin)"
  (( free >= need )) || { echo "opnsense-test: refused, short on memory"; return 1; }
}

# The image, checked, then unpacked; the unpacked file's hash goes to tofu, which checks the upload.
image() {
  local xz=$files/$IMAGE_XZ qcow=$files/${IMAGE_XZ%.xz}
  if [[ ! -f $qcow ]]; then
    curl -sS --fail --max-time 1800 -o "$xz.part" "$IMAGE_URL"
    echo "$IMAGE_SHA256  $xz.part" | sha256sum -c --quiet - || { rm -f "$xz.part"; echo "opnsense-test: the image does not match its pin; nothing built"; return 1; }
    mv "$xz.part" "$xz"
    xz -dc "$xz" > "$qcow.part" && mv "$qcow.part" "$qcow" && rm -f "$xz"
    echo "opnsense-test: image checked against $IMAGE_SHA256 and unpacked"
  fi
}

# The seed ISO: meta-data and a first-boot script, label cidata (FreeBSD's rc.d/nuageinit looks for that label).
seed_iso() {
  rm -rf "$files/seed" && mkdir -p "$files/seed"
  "$py" -I "$seed_py" seed "$settings" "$vlans" "$sshkey.pub" "$files/seed"
  xorriso -as mkisofs -quiet -o "$files/seed.iso" -V cidata -J -r "$files/seed"
}

# The variables for tofu: the unpacked image's and the seed ISO's hashes go to tofu, which checks the uploads.
write_vars() {
  python3 -I - "$settings" "$files" "$IMAGE_XZ" "$vars" <<'PY'
import hashlib, json, os, sys
s = json.load(open(sys.argv[1]))
files = sys.argv[2]
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()
image = os.path.join(files, sys.argv[3][:-3])
json.dump({
    "proxmox_node_name": s["proxmox_node_name"], "vnet": "dev",
    "image_path": image, "image_sha256": sha(image),
    "seed_iso_path": os.path.join(files, "seed.iso"), "seed_iso_sha256": sha(os.path.join(files, "seed.iso")),
    "vm": {"name": s["name"], "vm_id": 257, "cores": s["cores"], "memory_mb": s["memory_mb"], "disk_gb": s["disk_gb"]},
}, open(sys.argv[4], "w"))
PY
}

tofu_run() {
  if [[ $action == plan ]]; then image; seed_iso; write_vars; fi
  if [[ $action == destroy && ! -f $vars ]]; then
    [[ ! -s $state ]] || { echo "opnsense-test: the state holds resources but $vars is gone; run plan, then destroy" >&2; exit 1; }
    echo "opnsense-test: nothing to destroy"; return 0
  fi
  set -a
  # shellcheck source=/dev/null
  . "$keys/proxmox-dev.env"
  set +a
  tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
  tofu init -input=false -backend-config="path=$state" >/dev/null
  case $action in
    plan) tofu plan -input=false -var-file="$vars" -out="$plan" ;;
    apply)
      [[ -f $plan ]] || { echo "opnsense-test: no saved plan; run opnsense-test plan first" >&2; exit 1; }
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

vm() { ssh -i "$sshkey" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$files/known_hosts" "root@$addr" "$@"; }
wait_ssh() { # what for
  local _
  for _ in $(seq 1 60); do vm true 2>/dev/null && return 0; sleep 10; done
  echo "opnsense-test: no SSH to $addr after 10 minutes ($1)"; return 1
}
fetch() { # url sha256 out
  curl -sS --fail --max-time 300 -L -o "$3.part" "$1"
  echo "$2  $3.part" | sha256sum -c --quiet - || { rm -f "$3.part"; echo "opnsense-test: $(basename "$3") does not match its pin"; return 1; }
  mv "$3.part" "$3"
}

configure() {
  wait_ssh "first boot"
  local rel
  rel=$(vm uname -r)
  [[ $rel == 14.3-RELEASE* ]] || { echo "opnsense-test: the VM runs $rel, not 14.3-RELEASE; OPNsense 26.1 needs 14.3"; return 1; }
  echo "opnsense-test: the VM runs FreeBSD $rel"
  # Plan's condition 2: measure dev's reach to what the bootstrap fetches (the core tarball from GitHub,
  # packages from pkg.opnsense.org) before relying on it. On a failure, stop: opening egress is a firewall change.
  local u
  for u in https://github.com/ https://pkg.opnsense.org/; do
    vm fetch -q -T 20 -o /dev/null "$u" || { echo "opnsense-test: stopped, dev does not reach $u; no egress is opened (firewall change)"; return 1; }
    echo "opnsense-test: dev reaches $u"
  done
  # The proof's secrets, made here for this proof only. The hashes are SHA-512 crypt (openssl passwd -6),
  # which PHP's password_verify accepts; the box has no bcrypt.
  mkdir -p "$proof"
  [[ -f $proof/root.pass ]] || openssl rand -base64 24 > "$proof/root.pass"
  openssl passwd -6 -stdin < "$proof/root.pass" > "$proof/root.hash"
  openssl rand -base64 48 | openssl passwd -6 -stdin > "$proof/proofadmin.hash"   # no one keeps this password
  for f in client.secret user.pass stranger.pass; do [[ -f $proof/$f ]] || openssl rand -hex 24 > "$proof/$f"; done
  # The proof's CA and Keycloak's certificate for the box's address the VM reaches.
  if [[ ! -f $proof/ca.pem ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj "/CN=opnsense-test proof CA" \
      -keyout "$proof/ca.key" -out "$proof/ca.pem" 2>/dev/null
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=$kc_addr" \
      -keyout "$proof/kc.key" -out "$proof/kc.csr" 2>/dev/null
    openssl x509 -req -in "$proof/kc.csr" -CA "$proof/ca.pem" -CAkey "$proof/ca.key" -CAcreateserial -days 2 \
      -extfile <(printf 'subjectAltName=IP:%s\nextendedKeyUsage=serverAuth\n' "$kc_addr") -out "$proof/kc.pem" 2>/dev/null
  fi
  "$py" -I "$seed_py" config "$settings" "$vlans" "$sshkey.pub" "$proof" "$proof/config.xml"
  fetch "$BOOTSTRAP_URL" "$BOOTSTRAP_SHA256" "$files/opnsense-bootstrap.sh"
  fetch "$PLUGIN_URL" "$PLUGIN_SHA256" "$files/os-openid-connect.pkg"
  echo "opnsense-test: proof item 1: os-openid-connect.pkg sha256 $PLUGIN_SHA256 matched on the box; attestation: CI job plugin-pin"
  scp -q -i "$sshkey" -o BatchMode=yes -o UserKnownHostsFile="$files/known_hosts" \
    "$proof/config.xml" "$files/opnsense-bootstrap.sh" "$files/os-openid-connect.pkg" "root@$addr:/root/"
  # The seeded config goes in before the bootstrap, which keeps /conf without -f; at the first OPNsense
  # boot the importer finds /conf/config.xml and exits, so the seeded config is the first one used.
  vm 'install -d -m 755 /conf && install -m 600 /root/config.xml /conf/config.xml && rm /root/config.xml'
  echo "opnsense-test: bootstrapping OPNsense 26.1 (the VM reboots at the end)"
  vm 'sh /root/opnsense-bootstrap.sh -r 26.1 -y' || true   # the reboot drops the session
  sleep 30
  rm -f "$files/known_hosts"   # OPNsense makes new host keys
  wait_ssh "first OPNsense boot"
  vm 'opnsense-version'
  vm 'pkg add /root/os-openid-connect.pkg && rm /root/os-openid-connect.pkg /root/opnsense-bootstrap.sh'
  vm 'pkg info os-openid-connect | head -3'
}

# The proof's Keycloak: host network, so the box's nft table (role agent_box: 8443 only from VM 257's
# address and loopback) applies to it; its dev-file data lives in the container and goes with it.
keycloak_up() {
  "$py" -I "$seed_py" realm "$settings" "$proof" "$proof/realm.json"
  mkdir -p "$proof/kc" "$proof/kc-import"
  cp "$proof/kc.pem" "$proof/kc.key" "$proof/kc/"
  cp "$proof/realm.json" "$proof/kc-import/"
  openssl rand -hex 24 > "$proof/kc-admin.pass"
  podman rm -f "$KC_NAME" >/dev/null 2>&1 || true
  KC_BOOTSTRAP_ADMIN_PASSWORD=$(cat "$proof/kc-admin.pass") podman run -d --name "$KC_NAME" --network host \
    --userns=keep-id:uid=1000,gid=1000 -v "$proof/kc:/opt/keycloak/conf/proof:ro,Z" \
    -v "$proof/kc-import:/opt/keycloak/data/import:ro,Z" \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=proof-admin -e KC_BOOTSTRAP_ADMIN_PASSWORD \
    -e JAVA_OPTS_KC_HEAP="-Xms256m -Xmx1024m" \
    "$KEYCLOAK_IMAGE" start-dev --import-realm --http-enabled=false --https-port=8443 \
    --https-certificate-file=/opt/keycloak/conf/proof/kc.pem --https-certificate-key-file=/opt/keycloak/conf/proof/kc.key \
    --hostname="https://$kc_addr:8443" --features-disabled=dpop >/dev/null
  local _
  for _ in $(seq 1 60); do
    curl -sS --fail --max-time 5 --cacert "$proof/ca.pem" "https://$kc_addr:8443/realms/opnsense-proof/.well-known/openid-configuration" \
      -o "$proof/discovery.json" 2>/dev/null && break
    sleep 5
  done
  [[ -s $proof/discovery.json ]] || { echo "opnsense-test: Keycloak did not come up"; podman logs --tail 30 "$KC_NAME"; return 1; }
  ! grep -q dpop_signing_alg_values_supported "$proof/discovery.json" || { echo "opnsense-test: Keycloak still advertises DPoP"; return 1; }
  echo "opnsense-test: Keycloak 26.8.1 is up at https://$kc_addr:8443 (realm opnsense-proof, DPoP off)"
}
keycloak_down() {
  podman rm -f "$KC_NAME" >/dev/null 2>&1 || true
  rm -rf "$proof/kc" "$proof/kc-import" "$proof/kc-admin.pass" "$proof/discovery.json"
  echo "opnsense-test: Keycloak stopped and its data removed"
}

prove() {
  [[ -f $proof/root.pass ]] || { echo "opnsense-test: run configure first" >&2; return 1; }
  trap keycloak_down EXIT
  keycloak_up
  vm "fetch -q -T 20 -o /dev/null https://$kc_addr:8443/realms/opnsense-proof/.well-known/openid-configuration" \
    || { echo "opnsense-test: stopped, the VM does not reach Keycloak on the box over verified https"; return 1; }
  echo "opnsense-test: the VM reaches Keycloak over https, trusting the proof CA from its config.xml"
  vm 'cat /var/etc/cert.pem' > "$proof/gui.pem"
  "$py" -I "$libexec/opnsense-test-prove.py" "$addr" "$proof" "$sshkey" "$files/known_hosts"
}

case $action in
  plan | apply) guards; tofu_run ;;
  configure) configure ;;
  prove) prove ;;
  destroy)
    podman rm -f "$KC_NAME" >/dev/null 2>&1 || true
    tofu_run
    rm -rf "$proof" "$files/seed" "$files/seed.iso" "$files/known_hosts" "$files"/*.part "$vars"
    echo "opnsense-test: proof item 8: VM $VMID destroyed; proof folder removed"
    ;;
esac
