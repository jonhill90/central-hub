#!/usr/bin/env bash
# The secrets-store wrapper's own checks (hosts/ansible/roles/agent_box/files/secrets-store.sh), with stand-ins for curl
# and its helpers:
#   1. Dev only (D-0058 rule 10): with no store address in the settings, no dev inventory, an inventory that names no
#      store or two, or an address that is not the store the inventory names, every action refuses before any call.
#   2. With the address equal to the inventory's k8s_gitops_source_openbao_store_host, status reaches the store.
#   3. With no CA file beside the keys, it refuses before any call.
#   4. put, compare and reseed refuse until the settings' sops_copies is true (D-0058 rule 9), without calling the helper.
#   5. put hands the helper the path and key as arguments and the value on stdin only; a bad path or key is a usage error.
#   6. reseed refuses during a rebuild hold; without one it runs the helper's reseed, then takes a snapshot.
#   7. --prod reads only the prod settings, keys folder and inventory: dev's store address is refused, the prod store's
#      is reached, and prod recovery refuses before any call (D-0038 rule 5: prod gets no recovery shares).
# Usage: .github/hosts-check/tests/test_secrets_store_wrapper.sh   (needs python3 with PyYAML, openssl, flock)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin" "$t/libexec/ansible-venv/bin" "$t/keys/dev" "$t/keys/prod" "$t/keys/rebuild-dev/inventory" "$t/work/state" "$t/run"
ln -s "$(command -v python3)" "$t/libexec/ansible-venv/bin/python3"
cat > "$t/bin/curl" <<EOF
#!/bin/bash
echo "curl \$*" >> $t/calls
echo '{"initialized":true,"sealed":false}'
EOF
cat > "$t/libexec/secrets-store-kv.sh" <<EOF
#!/bin/bash
echo "kv \$*" >> $t/calls
cat > $t/kv-stdin
echo "kv helper ran \$1"
EOF
cat > "$t/run/secrets-store-snapshots.sh" <<EOF
#!/bin/bash
echo "snapshots \$1" >> $t/calls
EOF
chmod +x "$t/bin/curl" "$t/libexec/secrets-store-kv.sh" "$t/run/secrets-store-snapshots.sh"
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^work=.*|work=$t/work|" \
    -e "s|PATH=/usr/local/bin|PATH=$t/bin:/usr/local/bin|" \
    hosts/ansible/roles/agent_box/files/secrets-store.sh > "$t/run/secrets-store.sh"
grep -q "^keys=$t/keys" "$t/run/secrets-store.sh" && grep -q "^libexec=$t/libexec" "$t/run/secrets-store.sh" &&
  grep -q "^work=$t/work" "$t/run/secrets-store.sh" && grep -q "PATH=$t/bin:" "$t/run/secrets-store.sh" ||
  { echo "FAIL the test could not point the wrapper at its folders"; exit 1; }

settings() { echo "$1" > "$t/work/secrets-store.json"; }
inventory() { printf '%s\n' "$@" > "$t/keys/rebuild-dev/inventory/hosts.yml"; }
run() { : > "$t/calls"; rm -f "$t/kv-stdin"; bash "$t/run/secrets-store.sh" "$@" > "$t/out" 2>&1; rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls"); }
store_inv=("all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_gitops_source_openbao_store_host: bao-dev.invalid")

# 1
settings '{}'; inventory "${store_inv[@]}"; run status; r1a=$rc o1a=$out c1a=$calls
settings '{"address": "bao-dev.invalid"}'; rm -f "$t/keys/rebuild-dev/inventory/hosts.yml"; run status; r1b=$rc o1b=$out c1b=$calls
inventory "all:" "  vars:" "    other: 1"; run status; r1c=$rc o1c=$out c1c=$calls
inventory "${store_inv[@]}" "    k8s_workers:" "      vars:" "        k8s_gitops_source_openbao_store_host: bao-other.invalid"; run status; r1d=$rc o1d=$out c1d=$calls
settings '{"address": "bao-prod.invalid"}'; inventory "${store_inv[@]}"; run status; r1e=$rc o1e=$out c1e=$calls
if [[ $r1a -ne 0 && $o1a == *"no store address yet"* && $r1b -ne 0 && $o1b == *"dev inventory"*"is missing"* &&
      $r1c -ne 0 && $o1c == *"names no single dev store"* && $r1d -ne 0 && $o1d == *"names no single dev store"* &&
      $r1e -ne 0 && $o1e == *"is not the dev c1 store"* && -z $c1a$c1b$c1c$c1d$c1e ]]; then
  ok "1. no address, no inventory, no single store named, or another store: refused before any call"
else bad "1. $r1a $o1a | $r1b $o1b | $r1c $o1c | $r1d $o1d | $r1e $o1e"; fi

# 3 (before 2: no CA file yet)
settings '{"address": "bao-dev.invalid"}'
run status
if [[ $rc -ne 0 && $out == *"secrets-store-ca.crt is missing"* && -z $calls ]]; then ok "3. no CA file: refused before any call"
else bad "3. $rc $out"; fi
echo ca > "$t/keys/dev/secrets-store-ca.crt"

# 2
run status
if [[ $rc -eq 0 && $calls == *"https://bao-dev.invalid/v1/sys/health"* ]]; then ok "2. the dev store's address: status reaches it"
else bad "2. $rc $out $calls"; fi

# 4
r4=""
for s in '{"address": "bao-dev.invalid"}' '{"address": "bao-dev.invalid", "sops_copies": false}' '{"address": "bao-dev.invalid", "sops_copies": "true"}'; do
  settings "$s"
  run put c1/app/db password < <(printf value-Mx31); r4+="$rc:${calls:-none}:$([[ $out == *"wait for the owner's tap"* ]] && echo named) "
  run compare; r4+="$rc:${calls:-none}:$([[ $out == *"wait for the owner's tap"* ]] && echo named) "
  run reseed; r4+="$rc:${calls:-none}:$([[ $out == *"wait for the owner's tap"* ]] && echo named) "
done
if [[ $r4 != *"0:"* && $r4 != *"kv "* && $(grep -o named <<<"$r4" | wc -l) == 9 ]]; then ok "4. put, compare and reseed refuse until sops_copies is true, without the helper"
else bad "4. $r4"; fi

# 5
settings '{"address": "bao-dev.invalid", "sops_copies": true}'
run put c1/app/db password < <(printf 'value-Mx31')
r5a=$rc c5a=$calls s5a=$(cat "$t/kv-stdin" 2>/dev/null)
run put kv/dev/snapshot-mark taken < <(printf x); r5b=$rc c5b=$calls
run put c1/app 'bad key' < <(printf x); r5c=$rc
run put c1/app < <(printf x); r5d=$rc
if [[ $r5a -eq 0 && $c5a == "kv put https://bao-dev.invalid $t/keys/dev/secrets-store-ca.crt $t/keys/dev $t/libexec c1/app/db password" &&
      $s5a == value-Mx31 && $r5b -eq 2 && -z $c5b && $r5c -eq 2 && $r5d -eq 2 ]]; then
  ok "5. put passes path and key as arguments and the value on stdin only; bad ones are usage errors"
else bad "5. $r5a [$c5a] [$s5a] $r5b $r5c $r5d"; fi

# 6
date -u > "$t/work/state/secrets-store.rebuilding"
run reseed; r6a=$rc o6a=$out c6a=$calls
rm -f "$t/work/state/secrets-store.rebuilding"
run reseed
if [[ $r6a -ne 0 && $o6a == *"a rebuild is in progress"* && -z $c6a && $rc -eq 0 &&
      $calls == "kv reseed https://bao-dev.invalid $t/keys/dev/secrets-store-ca.crt $t/keys/dev $t/libexec"$'\n'"snapshots take" ]]; then
  ok "6. reseed refuses during a rebuild hold; otherwise the helper's reseed, then a snapshot"
else bad "6. $r6a $o6a | $rc $out | $calls"; fi

# 7
echo '{"address": "bao-dev.invalid"}' > "$t/work/secrets-store-prod.json"
printf '%s\n' "all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_gitops_source_openbao_store_host: bao-prod.invalid" > "$t/keys/prod/inventory-hosts.yml"
echo ca > "$t/keys/prod/secrets-store-ca.crt"
run --prod status; r7a=$rc o7a=$out c7a=$calls
echo '{"address": "bao-prod.invalid"}' > "$t/work/secrets-store-prod.json"
run --prod status; r7b=$rc c7b=$calls
run --prod recovery; r7c=$rc o7c=$out c7c=$calls
if [[ $r7a -ne 0 && $o7a == *"is not the prod c1 store"* && -z $c7a && $r7b -eq 0 && $c7b == *"https://bao-prod.invalid/v1/sys/health"* &&
      $c7b != *bao-dev* && $r7c -ne 0 && $o7c == *"prod gets no recovery shares"* && -z $c7c &&
      -s $t/keys/prod/openbao-admin-role-id ]]; then
  ok "7. --prod: dev's address refused, the prod store reached, prod recovery refused"
else bad "7. $r7a $o7a | $r7b $c7b | $r7c $o7c $c7c"; fi

exit $fail
