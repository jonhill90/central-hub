#!/usr/bin/env bash
# hosts/rebuild-k8s.sh's l2_report and the report it runs, role k8s_control_plane's files/l2-report.py (D-0062): one
# line per LoadBalancer Service with its address, its policy and the node holding its lease; PASS only when every
# Service with an address has a lease holder; FAIL on one with none, on no LoadBalancer Service at all, and on a
# failed read. The gateway stage runs it on dev only, and the gateway stage's l2 lines, and nothing else, reach the
# short log. With --kubectl (the role's lb tag, on the node) it reads with kubectl and lists the policies too. Runs
# the function from a copy with `kc` stubbed, and the script with a stub kubectl.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
script=$src/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^l2_report() {/,/^}/p' "$script" > "$t/fn.sh"
[ -s "$t/fn.sh" ] || { echo "FAIL: l2_report not found"; exit 1; }
check() { # name, output, must-contain, must-not-contain
  if [[ $2 == *"$3"* ]] && { [ -z "${4:-}" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi
}
svc() { # ns name type label ip
  local labels="{}" ingress="[]"
  [ -z "$4" ] || labels="{\"central-hub/l2-policy\": \"$4\"}"
  [ -z "$5" ] || ingress="[{\"ip\": \"$5\"}]"
  printf '{"metadata": {"namespace": "%s", "name": "%s", "labels": %s}, "spec": {"type": "%s"}, "status": {"loadBalancer": {"ingress": %s}}}' \
    "$1" "$2" "$labels" "$3" "$ingress"
}
lease() { printf '{"metadata": {"name": "%s"}, "spec": {"holderIdentity": "%s"}}' "$1" "$2"; }
# run <svc items> <lease items> [fail-read]: prints the output and the exit code on the last line.
run() {
  printf '{"items": [%s]}' "$1" > "$t/svc.json"; printf '{"items": [%s]}' "$2" > "$t/leases.json"
  FAILREAD=${3:-} T=$t repo=$src bash -c '
    kc() { [ -z "$FAILREAD" ] || return 1; case "$*" in *leases*) cat "$T/leases.json" ;; *) cat "$T/svc.json" ;; esac; }
    . "$1"; set +e; l2_report; echo "rc=$?"' _ "$t/fn.sh"
}
gw=$(svc gateway cilium-gateway-apps LoadBalancer "" 192.0.2.10)
adm=$(svc openbao openbao-admin LoadBalancer openbao-admin 192.0.2.11)
cip=$(svc default kubernetes ClusterIP "" "")
pend=$(svc media pending LoadBalancer "" "")
lgw=$(lease cilium-l2announce-gateway-cilium-gateway-apps node-a)
ladm=$(lease cilium-l2announce-openbao-openbao-admin node-b)

out=$(run "$gw,$adm,$cip,$pend" "$lgw,$ladm")
check "every address held: PASS, rc 0" "$out" "l2: PASS: every LoadBalancer Service" "rc=1"
check "the Gateway's line names its address, the general policy and its holder" "$out" \
  "l2: service gateway/cilium-gateway-apps address 192.0.2.10 policy general lease node-a"
check "a labelled Service names its own policy" "$out" "l2: service openbao/openbao-admin address 192.0.2.11 policy openbao-admin lease node-b"
check "a Service with no address yet is listed, not failed" "$out" "l2: service media/pending address none policy general lease none"
check "a ClusterIP Service is left out" "$out" "rc=0" "default/kubernetes"
check "the count line" "$out" "l2: 3 LoadBalancer Services, 0 with an address and no lease holder"

out=$(run "$gw,$adm" "$lgw")
check "an address with no lease holder: FAIL, rc 1" "$out" "l2: FAIL: an address no node announces" "l2: PASS"
check "its line says lease none" "$out" "openbao/openbao-admin address 192.0.2.11 policy openbao-admin lease none"
check "and the failing run's rc" "$out" "rc=1"

out=$(run "$gw" "$(lease cilium-l2announce-gateway-cilium-gateway-apps '')")
check "an empty holder counts as none" "$out" "lease none"
check "and fails" "$out" "rc=1"

out=$(run "$cip" "")
check "no LoadBalancer Service at all: FAIL" "$out" "l2: FAIL: no LoadBalancer Service"

out=$(run "$gw" "$lgw" yes)
check "a failed read: FAIL, rc 1" "$out" "l2: FAIL: the Services or the leases could not be read"
check "and rc 1" "$out" "rc=1"

# --kubectl: the script reads the three lists itself and prints the policies first.
mkdir -p "$t/bin"
cat > "$t/bin/kubectl" <<'K'
#!/usr/bin/env bash
[ -z "${KFAIL:-}" ] || { echo "forbidden" >&2; exit 1; }
case "$*" in
  *leases*) cat "$T/leases.json" ;;
  *ciliuml2announcementpolicies*) printf '{"items": [{"metadata": {"name": "pool"}, "spec": {"serviceSelector": {"matchExpressions": [{"key": "central-hub/l2-policy", "operator": "DoesNotExist"}]}}}]}' ;;
  *) cat "$T/svc.json" ;;
esac
K
chmod +x "$t/bin/kubectl"
py=$src/hosts/ansible/roles/k8s_control_plane/files/l2-report.py
printf '{"items": [%s]}' "$gw" > "$t/svc.json"; printf '{"items": [%s]}' "$lgw" > "$t/leases.json"
out=$(T=$t PATH="$t/bin:$PATH" python3 -I "$py" --kubectl; echo "rc=$?")
check "--kubectl: the policy line" "$out" 'l2: policy pool serviceSelector {"matchExpressions": [{"key": "central-hub/l2-policy", "operator": "DoesNotExist"}]}'
check "--kubectl: the Service line and PASS" "$out" "lease node-a" "rc=1"
check "--kubectl: rc 0" "$out" "rc=0"
out=$(T=$t KFAIL=1 PATH="$t/bin:$PATH" python3 -I "$py" --kubectl; echo "rc=$?")
check "--kubectl: a refused read fails" "$out" "l2: FAIL: the Services, leases or policies could not be read"
check "--kubectl: rc 1" "$out" "rc=1"
out=$(python3 -I "$py" 2>&1; echo "rc=$?")
check "no arguments: usage, rc 2" "$out" "rc=2"

# The gateway stage: dev runs the report after the playbook, other envs don't, and a failed report fails the stage.
sed -n '/^run_stage() {/,/^}/p' "$script" > "$t/stage.sh"
stage() { # env, report rc
  ENV_NAME=$1 RC=$2 bash -c 'ap() { echo "AP $*"; }; l2_report() { echo L2; return "$RC"; }
    . "$1"; set +e; (set -e; run_stage gateway); echo "rc=$?"' _ "$t/stage.sh"
}
out=$(stage dev 0)
check "dev: the playbook, then the report" "$out" $'AP playbooks/k8s-gateway.yml\nL2\nrc=0'
out=$(stage dev 1)
check "dev: a failed report fails the stage" "$out" "rc=1"
out=$(stage prod 1)
check "prod: no report" "$out" "rc=0" "L2"
# A failed run's capture reads it too.
sed -n '/^runner_capture_diag() {/,/^}/p' "$script" | grep -q '^    l2_report || true$' \
  && echo "ok   a failed run's capture runs l2_report" || { echo "FAIL the capture has no l2_report"; fail=1; }

# The short log takes the gateway stage's l2 lines and nothing else.
sed -n '/^  if \[ "\$s" = gateway \]; then/,/^  fi$/p' "$script" > "$t/block.sh"
[ -s "$t/block.sh" ] || { echo "FAIL: short-log block not found"; exit 1; }
cat > "$t/raw" <<'R'
===== apps
l2: service other/stage address 198.51.100.9 policy general lease x
===== gateway
TASK [smoke | Remove the test app]
l2: service gateway/cilium-gateway-apps address 192.0.2.10 policy general lease node-a
l2: PASS: every LoadBalancer Service with an address has a lease holder
token=abc
===== certs
l2: service later/stage address 198.51.100.8 policy general lease y
R
: > "$t/log"
out=$(s=gateway raw="$t/raw" log="$t/log" bash -c '. "$1"' _ "$t/block.sh"; cat "$t/log")
check "the gateway stage's l2 lines reach the short log" "$out" "  gateway: l2: service gateway/cilium-gateway-apps address 192.0.2.10"
check "its PASS line too" "$out" "  gateway: l2: PASS:"
check "no other stage's lines" "$out" "PASS" "198.51.100.9"
check "no later stage's lines" "$out" "PASS" "198.51.100.8"
check "nothing else from the stage" "$out" "PASS" "token=abc"
: > "$t/log"
out=$(s=apps raw="$t/raw" log="$t/log" bash -c '. "$1"' _ "$t/block.sh"; cat "$t/log")
[ -z "$out" ] && echo "ok   another stage copies nothing" || { echo "FAIL another stage copied: $out"; fail=1; }
exit $fail
