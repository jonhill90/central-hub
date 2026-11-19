#!/usr/bin/env bash
# The three delete tasks of role k8s_observability (Helm's old release Secrets, Loki's emptyDir StatefulSet), run by real
# ansible-playbook on localhost against a stand-in kubectl, with the tags the box runs only for the deletes (`deletes`):
#   1. Check mode with the three Argo CD switches true: the reads print the Secrets each delete would remove (metrics-server,
#      loki, alloy, kube-prometheus-stack), and no delete is called.
#   2. Check mode with logs not under Argo CD and a StatefulSet without claim templates: the output says Loki's delete would
#      remove the StatefulSet and its pod, and no delete is called.
#   3. Check mode with a StatefulSet that has claim templates: the output says it would remove nothing.
#   4. Check mode with nothing to remove: the output says "nothing" for each Secret read, still no delete.
#   5. The same cases without --check still call the deletes (the reads did not replace them).
# Usage: .github/hosts-check/tests/test_observability_deletes.sh   (needs ansible-playbook and the collections)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$t/bin"

cat > "$t/bin/kubectl" <<'SH'
#!/bin/bash
echo "$*" >> "$T/calls"
case "$*" in
  *"get secret -l owner=helm,name="*)
    [ -e "$T/nosecrets" ] && exit 0
    all="$*"; n=${all#*name=}; n=${n%% *}
    echo "secret/sh.helm.release.v1.$n.v1" ;;
  *"get statefulset loki"*) cat "$T/sts" ;;
esac
exit 0
SH
chmod +x "$t/bin/kubectl"

cat > "$t/inventory.yml" <<EOF2
all:
  children:
    k8s_control_plane:
      hosts:
        cp-a:
          ansible_host: localhost
          ansible_connection: local
          ansible_become: false
          ansible_python_interpreter: $(command -v python3)
EOF2

cat > "$t/play.yml" <<'EOF2'
- hosts: k8s_control_plane
  roles:
    - k8s_observability
EOF2

run() { # run <extra ansible-playbook args...>
  : > "$t/calls"
  (cd "$root/hosts/ansible" && PATH="$t/bin:$PATH" T="$t" ANSIBLE_NOCOLOR=1 ANSIBLE_STDOUT_CALLBACK=default \
    ANSIBLE_ROLES_PATH="$root/hosts/ansible/roles" \
    ansible-playbook -i "$t/inventory.yml" "$t/play.yml" --tags deletes -e k8s_observability_zone=example.com "$@") > "$t/out" 2>&1
  rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls")
}
all_true=(-e k8s_observability_metrics_server_by_argocd=true -e k8s_observability_logs_by_argocd=true -e k8s_observability_metrics_by_argocd=true)
loki_false=(-e k8s_observability_metrics_server_by_argocd=true -e k8s_observability_logs_by_argocd=false -e k8s_observability_metrics_by_argocd=true)

# 1
printf '' > "$t/sts"
run --check "${all_true[@]}"
if [ $rc -eq 0 ] && grep -q "metrics-server's delete would remove: secret/sh.helm.release.v1.metrics-server.v1" <<< "$out" &&
   grep -q "loki's delete would remove: secret/sh.helm.release.v1.loki.v1" <<< "$out" &&
   grep -q "alloy's delete would remove: secret/sh.helm.release.v1.alloy.v1" <<< "$out" &&
   grep -q "kube-prometheus-stack's delete would remove: secret/sh.helm.release.v1.kube-prometheus-stack.v1" <<< "$out" &&
   ! grep -qE ' delete ' <<< "$calls"; then
  ok "1. check mode, switches true: the Secrets each delete would remove are printed, no delete is called"
else bad "1. rc $rc: $(tail -25 "$t/out")"; fi

# 2
printf 'loki ' > "$t/sts"
run --check "${loki_false[@]}"
if [ $rc -eq 0 ] && grep -q "Loki's delete would remove: StatefulSet loki and its pod" <<< "$out" && ! grep -qE ' delete ' <<< "$calls"; then
  ok "2. check mode, StatefulSet without claim templates: the output names it, no delete is called"
else bad "2. rc $rc: $(tail -25 "$t/out")"; fi

# 3
printf 'loki data' > "$t/sts"
run --check "${loki_false[@]}"
if [ $rc -eq 0 ] && grep -q "Loki's delete would remove: nothing" <<< "$out" && ! grep -qE ' delete ' <<< "$calls"; then
  ok "3. check mode, StatefulSet with claim templates: the output says nothing"
else bad "3. rc $rc: $(tail -25 "$t/out")"; fi

# 4
: > "$t/nosecrets"; printf '' > "$t/sts"
run --check "${all_true[@]}"
if [ $rc -eq 0 ] && [ "$(grep -c "delete would remove: nothing" <<< "$out")" -ge 4 ] && ! grep -qE ' delete ' <<< "$calls"; then
  ok "4. check mode, no Secrets: each read says nothing"
else bad "4. rc $rc: $(tail -25 "$t/out")"; fi
rm -f "$t/nosecrets"

# 5
printf 'loki ' > "$t/sts"
run "${loki_false[@]}"
if [ $rc -eq 0 ] && grep -q 'delete statefulset loki' <<< "$calls" && grep -q 'delete secret -l owner=helm,name=metrics-server' <<< "$calls"; then
  ok "5. without --check the deletes still run"
else bad "5. rc $rc: $(tail -25 "$t/out")"; fi
exit $fail
