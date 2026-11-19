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
# Every default must be exactly "" and every task that writes the drop-in must be gated; the check reads the YAML.
gate=$(python3 - "$role/defaults/main.yml" "$role/tasks/main.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for k in ("system_reserved", "kube_reserved", "eviction_hard"):
    assert d["k8s_node_kubelet_%s_memory" % k] == "", k
t = [x for x in yaml.safe_load(open(sys.argv[2])) if x.get("name", "").startswith("step6a")]
assert len(t) == 3, len(t)
for x in t:
    assert x["when"] == "k8s_node_kubelet_system_reserved_memory | length > 0", x["name"]
print("gated")
PY
)
[ "$gate" = gated ] && ok "2 all three defaults are empty and all three step6a tasks are gated on the reservation" || bad "2 a default is not empty or a task is not gated: $gate"
# The assignment must sit inside the dev branch: kubelet_vars=() then "if dev", the -e lines, then "fi".
blk=$(awk '/^kubelet_vars=\(\)$/{f=1;n=0;next} f{n++; b[n]=$0; if($0=="fi"){for(i=1;i<=n;i++)print b[i]; exit}}' "$script")
if [ "$(printf '%s\n' "$blk" | head -1)" = 'if [ "$ENV_NAME" = dev ]; then' ] &&
   printf '%s\n' "$blk" | sed -n 2p | grep -q '^  kubelet_vars=(-e "k8s_node_kubelet_system_reserved_memory=' &&
   [ "$(printf '%s\n' "$blk" | grep -c 'k8s_node_kubelet_')" = 3 ] &&
   [ "$(grep -c '"${kubelet_vars\[@\]}"' "$script")" = 2 ] &&
   grep -Eq 'ap "\$repo/hosts/ansible/playbooks/k8s.yml" "\$\{kubelet_vars\[@\]\}"' "$script" &&
   grep -Eq 'cluster\) wait_ssh && ap playbooks/k8s.yml "\$\{kubelet_vars\[@\]\}"' "$script"; then
  ok "3 both k8s.yml runs get the variables, set only inside the dev branch"
else bad "3 kubelet_vars is not set only under the dev branch, or a k8s.yml run lacks it"; fi
exit "$fail"
