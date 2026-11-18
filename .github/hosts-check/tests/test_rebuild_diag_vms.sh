#!/usr/bin/env bash
# rebuild diag's first sections, offline: each dev VM's memory and CPU from the Proxmox guest list (VM IDs 250-257
# only), the node's memory, and each dev node's free memory, load and pressure. The token goes to curl on stdin,
# never in its arguments. Made-up values.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/ansible/roles/agent_box/files/rebuild.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^  px_get() { # path after \/api2\/json$/,/^  echo "== argocd applications"$/p' "$src" | sed '$d' > "$t/block.sh"
[ -s "$t/block.sh" ] || { echo "FAIL: block not found"; exit 1; }
mkdir -p "$t/bin" "$t/keys" "$t/inv"
scheme=https
printf 'PROXMOX_VE_ENDPOINT=%s\nPROXMOX_VE_API_TOKEN=agent@pve!dev=SECRETTOKEN\n' "$scheme://node.invalid:8006/" > "$t/keys/proxmox-dev.env"
printf 'proxmox_node_name = "examplehv01"\n' > "$t/keys/dev-vms.tfvars"
cat > "$t/bin/curl" <<'C'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_ARGV"; cat >> "$FAKE_STDIN"
[ -n "${FAKE_FAIL:-}" ] && exit 22
case "${*: -1}" in
  */cluster/resources?type=vm) echo '{"data":[{"vmid":250,"status":"running","mem":3060000000,"maxmem":3221225472,"cpu":0.91,"maxcpu":2},{"vmid":251,"status":"running","mem":5000000000,"maxmem":6442450944,"cpu":0.4,"maxcpu":4},{"vmid":258,"status":"running","mem":1,"maxmem":1,"cpu":0,"maxcpu":2},{"vmid":300,"status":"stopped","mem":0,"maxmem":2147483648,"cpu":0,"maxcpu":2}]}' ;;
  */nodes/examplehv01/status) echo '{"data":{"cpu":0.35,"memory":{"total":33582403584,"used":31000000000,"available":2582403584},"swap":{"used":1073741824,"total":8589934592}}}' ;;
  *) exit 22 ;;
esac
C
cat > "$t/bin/ansible" <<'A'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_ANSIBLE"
echo "[WARNING]: interpreter discovery"
echo "dalcpkube01 | CHANGED | rc=0 >>"
echo "Mem:           2949        2801          60"
A
chmod +x "$t/bin/curl" "$t/bin/ansible"
run() { : > "$t/argv"; : > "$t/stdin"; : > "$t/ansible"
  PATH="$t/bin:$PATH" keys="$t/keys" inventory="$t/inv" work="$t" FAKE_ARGV="$t/argv" FAKE_STDIN="$t/stdin" FAKE_ANSIBLE="$t/ansible" FAKE_FAIL=${FAKE_FAIL:-} \
    bash -c 'set -euo pipefail; . "$1"; echo "rc=$?"' _ "$t/block.sh" 2>&1; }
check() { if [[ $2 == *"$3"* ]] && { [ -z "${4:-}" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
out=$(run)
check "the control plane's memory and CPU on Proxmox" "$out" "vmid=250 status=running mem=2918 of 3072 MiB cpu=91% of 2 vCPU"
check "the worker's too" "$out" "vmid=251 status=running mem=4768 of 6144 MiB cpu=40% of 4 vCPU"
check "guests outside 250-257 are left out" "$out" "rc=0" "vmid=258"
check "VM 300 is left out" "$out" "rc=0" "vmid=300"
check "the node's memory, swap and CPU" "$out" "node memory total 32026 used 29563 available 2462 MiB; swap used 1024 of 8192 MiB; cpu 35%"
check "each dev node's free memory" "$out" "Mem:           2949"
check "ansible's warnings are dropped" "$out" "rc=0" "[WARNING]"
check "it reads the control plane and the workers" "$(cat "$t/ansible")" "k8s_control_plane:k8s_workers" ""
check "free, load and pressure are read" "$(cat "$t/ansible")" "free -m; cat /proc/loadavg; for f in memory cpu" ""
if grep -q SECRETTOKEN "$t/argv"; then echo "FAIL: the token is in curl's arguments"; fail=1; else echo "ok   the token is not in curl's arguments"; fi
grep -q 'header = "Authorization: PVEAPIToken=agent@pve!dev=SECRETTOKEN"' "$t/stdin" && echo "ok   the token goes in on stdin" || { echo "FAIL: the header is not on stdin"; fail=1; }
if grep -q -- "-X" "$t/argv"; then echo "FAIL: a method other than GET"; fail=1; else echo "ok   GET only"; fi
out=$(FAKE_FAIL=1 run)
check "a failed guest list prints one line and goes on" "$out" "(the guest list could not be read)" "SECRETTOKEN"
check "a failed node read prints one line and goes on" "$out" "(the node status could not be read)" ""
check "the node sections still run" "$out" "rc=0" ""
[ "$fail" = 0 ] || exit 1
echo "rebuild diag VM stats: all checks passed"
