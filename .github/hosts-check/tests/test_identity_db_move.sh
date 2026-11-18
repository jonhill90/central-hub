#!/usr/bin/env bash
# playbooks/k8s-identity-db-move.yml (TASK-0225) run by real ansible-playbook on localhost against a stand-in kubectl (fake
# values only), with the cluster's answers set per case:
#   1. Default (k8s_identity_move_delete false): the rehearsal runs, nothing is stopped, deleted or applied, the rehearsal
#      dump is removed, and the output says nothing was done.
#   2. k8s_identity_move_delete=true: Keycloak is stopped first, then the final dump, then the StatefulSet, claim and volume
#      are deleted in that order, then the database manifest is applied (local-path claim, no PersistentVolume), then the
#      dump is loaded and Keycloak is started again; the PASS line appears and the dumps are removed.
#   3. A claim already on local-path: SKIP, nothing else runs.
#   4. A cluster labelled env dev, or with no env label at all: refused before any kubectl call.
#   5. Rows after the load differ from the rows before: the run fails and the dump is kept.
# Usage: .github/hosts-check/tests/test_identity_db_move.sh   (needs ansible-playbook)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$t/bin" "$t/ident"

cat > "$t/bin/kubectl" <<'SH'
#!/bin/bash
echo "$*" >> "$T/calls"
args="$*"
case $args in
  *"get pvc"*) cat "$T/class" ;;
  *"get storageclass"*) echo storageclass.storage.k8s.io/local-path ;;
  *"get pod"*"jsonpath={.status.phase}"*) echo -n Running ;;
  *"get pod"*"--ignore-not-found"*) ;;
  *"get keycloak"*) echo -n 2 ;;
  *"get statefulset"*"status.replicas"*) echo -n 0 ;;
  *"pg_dumpall"*) printf -- '-- fake dump\n-- PostgreSQL database cluster dump complete\n' ;;
  *"select (select count"*) if [ -e "$T/deleted" ] && [ -n "${AFTER_COUNT:-}" ]; then echo "$AFTER_COUNT"; else echo "1 5 7"; fi ;;
  *"dropdb"*) ;;
  *"psql"*"-d postgres"*) cat > /dev/null ;;
  *"delete pv sso-postgres"*) : > "$T/deleted" ;;
  *"diff"*) exit 1 ;;
esac
exit 0
SH
chmod +x "$t/bin/kubectl"

inventory() { # inventory <env>: one control-plane host labelled with the env; "none" sets no label at all
  local label="k8s_gitops_cluster_labels: {env: $1}"
  [ "$1" = none ] && label="k8s_unrelated: true"
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
          $label
EOF2
}

run() { # run [extra args...]
  : > "$t/calls"; rm -rf "$t/ident/"* "$t/move" "$t/deleted"
  (cd "$root/hosts/ansible" && PATH="$t/bin:$PATH" T="$t" ANSIBLE_NOCOLOR=1 ANSIBLE_STDOUT_CALLBACK=default \
    ansible-playbook -i "$t/inventory.yml" playbooks/k8s-identity-db-move.yml \
    -e "k8s_identity_dir=$t/ident" -e "k8s_identity_move_dir=$t/move" -e k8s_identity_zone=example.com \
    -e k8s_identity_owner_username=owner "$@") > "$t/out" 2>&1
  rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls")
}
line_of() { grep -n -m1 -- "$1" "$t/calls" | cut -d: -f1; }

inventory prod
# 1
printf '' > "$t/class"
run
if [ $rc -eq 0 ] && ! grep -qE ' (delete|patch|apply) ' <<< "$calls" && grep -q 'nothing is stopped or deleted' <<< "$out" \
   && [ -d "$t/move" ] && ! ls "$t/move"/* >/dev/null 2>&1; then
  ok "default run: the rehearsal only, nothing stopped, deleted or applied, no dump left"
else bad "default run (rc $rc): $(tail -15 "$t/out")"; fi

# 2
run -e k8s_identity_move_delete=true
a=$(line_of 'patch keycloak sso --type merge -p {"spec":{"instances":0}}'); b=$(grep -n 'pg_dumpall' "$t/calls" | tail -1 | cut -d: -f1)
c=$(line_of 'delete statefulset'); d=$(line_of 'delete pvc'); e=$(line_of 'delete pv sso-postgres'); f=$(line_of 'apply -f'); g=$(line_of 'instances":2')
if [ $rc -eq 0 ] && [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$d" ] && [ -n "$e" ] && [ -n "$f" ] && [ -n "$g" ] \
   && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ] && [ "$d" -lt "$e" ] && [ "$e" -lt "$f" ] && [ "$f" -lt "$g" ]; then
  ok "the move: stop, dump, delete statefulset, claim, volume, apply, start again, in that order"
else bad "the move order (rc $rc: $a $b $c $d $e $f $g): $(tail -15 "$t/out")"; fi
grep -q 'PASS: identity-db-move' <<< "$out" && [ ! -e "$t/move" ] && ok "the PASS line, and the dumps are removed" || bad "no PASS line or dumps left"
m=$t/ident/database.yaml
if [ -f "$m" ] && grep -q 'storageClassName: local-path' "$m" && ! grep -q 'kind: PersistentVolume$' "$m"; then
  ok "the applied manifest claims local-path and holds no PersistentVolume"
else bad "the applied manifest: $(cat "$m" 2>/dev/null | head -5)"; fi

# 3
printf 'local-path' > "$t/class"
run -e k8s_identity_move_delete=true
if [ $rc -eq 0 ] && grep -q 'SKIP: identity-db-move' <<< "$out" && ! grep -qE ' (exec|delete|patch|apply) ' <<< "$calls"; then
  ok "a claim already on local-path: SKIP, nothing else runs"
else bad "already moved (rc $rc): $(tail -10 "$t/out")"; fi

# 4
printf '' > "$t/class"
inventory dev; run -e k8s_identity_move_delete=true
if [ $rc -ne 0 ] && grep -q 'moves prod' <<< "$out" && [ ! -s "$t/calls" ]; then
  ok "env dev is refused before any kubectl call"
else bad "env dev (rc $rc)"; fi

# 4b
inventory none; run -e k8s_identity_move_delete=true
if [ $rc -ne 0 ] && grep -q 'moves prod' <<< "$out" && [ ! -s "$t/calls" ]; then
  ok "a host with no env label is refused before any kubectl call"
else bad "no env label (rc $rc)"; fi

# 5
inventory prod
printf '' > "$t/class"
AFTER_COUNT="1 4 7" run -e k8s_identity_move_delete=true
if [ $rc -ne 0 ] && [ -s "$t/move/dump.sql" ] && ! grep -q 'PASS: identity-db-move' <<< "$out" && ! grep -q 'instances":2' <<< "$calls"; then
  ok "rows that differ after the load: the run fails, the dump is kept, Keycloak is not started"
else bad "differing rows (rc $rc): $(tail -10 "$t/out")"; fi
exit $fail
