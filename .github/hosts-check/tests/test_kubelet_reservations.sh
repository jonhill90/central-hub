#!/usr/bin/env bash
# The kubelet memory reservations of role k8s_node (dev worker lost under Keycloak, 2026-11-19): renders the drop-in
# template with the dev values from hosts/rebuild-k8s.sh and checks:
#   1. The rendered file is a KubeletConfiguration with systemReserved, kubeReserved and evictionHard memory.available
#      set to the dev values, and the other hard thresholds kept.
#   2. The role's defaults are empty (prod writes nothing) and every task that writes the drop-in is gated on them.
#   3. rebuild-k8s.sh passes the three variables to both k8s.yml runs (the cluster stage and the idempotency check),
#      and only on dev.
# Usage: .github/hosts-check/tests/test_kubelet_reservations.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
role=hosts/ansible/roles/k8s_node
script=hosts/rebuild-k8s.sh
val() { sed -n "s/^$1=\([0-9A-Za-z]*\)\$/\1/p" "$script"; }
sys=$(val DEV_KUBELET_SYSTEM_RESERVED_MEMORY); kube=$(val DEV_KUBELET_KUBE_RESERVED_MEMORY); ev=$(val DEV_KUBELET_EVICTION_HARD_MEMORY)
[ -n "$sys" ] && [ -n "$kube" ] && [ -n "$ev" ] || { echo "FAIL could not read the DEV_KUBELET_* values from $script"; exit 1; }
out=$(python3 - "$role/templates/kubelet-reserve.conf.j2" "$sys" "$kube" "$ev" <<'PY'
import sys, jinja2, yaml
tpl, sysm, kube, ev = sys.argv[1:5]
text = jinja2.Template(open(tpl).read()).render(
    ansible_managed="x", k8s_node_kubelet_system_reserved_memory=sysm,
    k8s_node_kubelet_kube_reserved_memory=kube, k8s_node_kubelet_eviction_hard_memory=ev)
d = yaml.safe_load(text)
assert d["kind"] == "KubeletConfiguration", d
assert d["systemReserved"]["memory"] == sysm
assert d["kubeReserved"]["memory"] == kube
assert d["evictionHard"]["memory.available"] == ev
for k in ("nodefs.available", "nodefs.inodesFree", "imagefs.available", "imagefs.inodesFree"):
    assert k in d["evictionHard"], k
print("rendered")
PY
) && [ "$out" = rendered ] && ok "1 the drop-in renders as a KubeletConfiguration with the dev values ($sys, $kube, $ev)" || bad "1 the drop-in did not render right: $out"
if grep -Eq '^k8s_node_kubelet_(system_reserved|kube_reserved|eviction_hard)_memory: ""$' "$role/defaults/main.yml" &&
   [ "$(grep -c '^  when: k8s_node_kubelet_system_reserved_memory | length > 0$' "$role/tasks/main.yml")" = 3 ]; then
  ok "2 the defaults are empty and all three tasks are gated on the reservation"
else bad "2 a default is not empty or a task is not gated"; fi
if [ "$(grep -c '"${kubelet_vars\[@\]}"' "$script")" = 2 ] && grep -Eq 'ap "\$repo/hosts/ansible/playbooks/k8s.yml" "\$\{kubelet_vars\[@\]\}"' "$script" &&
   grep -Eq 'cluster\) wait_ssh && ap playbooks/k8s.yml "\$\{kubelet_vars\[@\]\}"' "$script" &&
   grep -Eq '^if \[ "\$ENV_NAME" = dev \]; then$' "$script" && grep -q '^kubelet_vars=()$' "$script"; then
  ok "3 both k8s.yml runs get the variables, set only on dev"
else bad "3 a k8s.yml run does not get kubelet_vars"; fi
exit "$fail"
