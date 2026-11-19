#!/usr/bin/env bash
# The secrets-store wrapper's own checks (hosts/ansible/roles/agent_box/files/secrets-store.sh), with stand-ins for curl
# and its helpers:
#   1. Dev only (D-0058 rule 10): with no store address in the settings, no dev inventory, an inventory that names no
#      store or two, or an address that is not the store the inventory names, every action refuses before any call.
#   2. With the address equal to the inventory's k8s_gitops_source_openbao_store_host, status reaches the store on its
#      admin address.
#   3. With no CA file beside the keys, it refuses before any call.
#   4. put, compare and reseed refuse until the settings' sops_copies is true (D-0058 rule 9), without calling the helper.
#   5. put hands the helper the path and key as arguments and the value on stdin only; a bad path or key is a usage error.
#   6. reseed refuses during a rebuild hold; without one it runs the helper's reseed, then takes a snapshot.
#   7. --prod reads only the prod settings, keys folder and inventory: dev's store address is refused, the prod store's
#      is reached on prod's admin address, and prod recovery refuses before any call (D-0038 rule 5: prod gets no
#      recovery shares).
#   8. No admin address, no call (D-0062: the box's only path to the store): with no rebuild copy of the dev inventory,
#      a copy without k8s_gitops_source_openbao_admin_address, or a prod inventory without it, every action refuses
#      before any call and says so; a gateway address in the dev inventory is never used.
#   9. put-apps refuses until sops_copies is true and on a missing file or a bad line, before any write; otherwise each
#      <name>=<value> line of the environment's secret-source file goes to the helper as put c1/<name> value, the value
#      on stdin byte for byte (an = inside it kept), comments and blank lines skipped; then each KEY=value line of the
#      identity values file as put c1/identity KEY; --prod reads prod's files only, and also puts the DNS-01 token,
#      trimmed, as put c1/cloudflare-api-token value. A missing identity or token file, a bad identity line or a blank
#      token writes nothing.
#  10. The store's admin address (D-0062): on dev the rebuild's copy of the dev inventory's (a settings value alone is
#      not used: with no copy yet, refused), on prod the prod inventory's
#      k8s_gitops_source_openbao_admin_address; set, every call goes there by the store's name (curl and the helpers),
#      one that is not IPv4, or two in the prod inventory, is refused before any call.
#  11. put and put-apps write nothing during a rebuild hold, on dev and with --prod (a key in the fresh store would make
#      restore-rebuilt refuse); with the hold gone, both run again.
# Usage: .github/hosts-check/tests/test_secrets_store_wrapper.sh   (needs python3 with PyYAML, openssl, flock)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin" "$t/libexec/ansible-venv/bin" "$t/keys/dev" "$t/keys/prod" "$t/work/openbao-prod/inventory" "$t/keys/rebuild-dev/inventory" "$t/work/state" "$t/run"
ln -s "$(command -v python3)" "$t/libexec/ansible-venv/bin/python3"
cat > "$t/bin/curl" <<EOF
#!/bin/bash
echo "curl \$*" >> $t/calls
echo '{"initialized":true,"sealed":false}'
EOF
cat > "$t/libexec/secrets-store-kv.sh" <<EOF
#!/bin/bash
echo "kv \$*" >> $t/calls
echo "\${SECRETS_STORE_RESOLVE:-unset}" > $t/kv-resolve
cat > $t/kv-stdin
{ printf '%s [' "\${*: -2}"; cat $t/kv-stdin; printf ']\n'; } >> $t/kv-log
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
store_inv=("all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_gitops_source_openbao_store_host: bao-dev.invalid"
           "        k8s_gitops_source_gateway_address: 192.0.2.10")
# The store's admin address, as a dev rebuild writes it into its copy of the dev inventory, and as prod's inventory has it.
dev_inv=$t/work/rebuild-dev/inventory/hosts.yml
admin_copy() { mkdir -p "$(dirname "$dev_inv")"; printf '%s\n' "all:" "  vars:" "    k8s_gitops_source_openbao_admin_address: ${1:-192.0.2.40}" > "$dev_inv"; }
admin_copy
prod_admin="        k8s_gitops_source_openbao_admin_address: 192.0.2.41"

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
if [[ $rc -eq 0 && $calls == *"--resolve bao-dev.invalid:443:192.0.2.40 "*"https://bao-dev.invalid/v1/sys/health"* && $calls != *192.0.2.10* ]]; then ok "2. the dev store's address: status reaches it, on its admin address"
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
      $s5a == value-Mx31 && $(cat "$t/kv-resolve") == bao-dev.invalid:443:192.0.2.40 && $r5b -eq 2 && -z $c5b && $r5c -eq 2 && $r5d -eq 2 ]]; then
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
printf '%s\n' "all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_gitops_source_openbao_store_host: bao-prod.invalid" "$prod_admin" > "$t/work/openbao-prod/inventory/hosts.yml"
echo ca > "$t/keys/prod/secrets-store-ca.crt"
run --prod status; r7a=$rc o7a=$out c7a=$calls
echo '{"address": "bao-prod.invalid"}' > "$t/work/secrets-store-prod.json"
run --prod status; r7b=$rc c7b=$calls
run --prod recovery; r7c=$rc o7c=$out c7c=$calls
if [[ $r7a -ne 0 && $o7a == *"is not the prod c1 store"* && -z $c7a && $r7b -eq 0 && $c7b == *"https://bao-prod.invalid/v1/sys/health"* &&
      $c7b != *bao-dev* && $c7b == *"--resolve bao-prod.invalid:443:192.0.2.41 "* && $r7c -ne 0 && $o7c == *"prod gets no recovery shares"* && -z $c7c &&
      -s $t/keys/prod/openbao-admin-role-id ]]; then
  ok "7. --prod: dev's address refused, the prod store reached on its admin address, prod recovery refused"
else bad "7. $r7a $o7a | $r7b $c7b | $r7c $o7c $c7c"; fi

# 8
settings '{"address": "bao-dev.invalid"}'
r8=""
rm -f "$dev_inv"; run status; r8+="$rc:${calls:-none}:$([[ $out == *"the dev store has no admin address"*"refused"* ]] && echo named) "
printf '%s\n' "all:" "  vars:" "    other: 1" > "$dev_inv"; run status; r8+="$rc:${calls:-none}:$([[ $out == *"the dev store has no admin address"* ]] && echo named) "
admin_copy
printf '%s\n' "all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_gitops_source_openbao_store_host: bao-prod.invalid" > "$t/work/openbao-prod/inventory/hosts.yml"
echo '{"address": "bao-prod.invalid"}' > "$t/work/secrets-store-prod.json"
run --prod status; r8+="$rc:${calls:-none}:$([[ $out == *"the prod store has no admin address"*"openbao-prod gitops"* ]] && echo named) "
printf '%s\n' "all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_gitops_source_openbao_store_host: bao-prod.invalid" "$prod_admin" > "$t/work/openbao-prod/inventory/hosts.yml"
if [[ $r8 == "1:none:named 1:none:named 1:none:named " ]]; then ok "8. no admin address (no dev copy, a copy without one, or a prod inventory without one): refused before any call"
else bad "8. $r8"; fi

# 9
settings '{"address": "bao-dev.invalid"}'
mkdir -p "$t/work/rebuild-dev"
printf '%s\n' 'GRAFANA_CLIENT_SECRET=g=1' 'PASSWORD_OWNER=pw-owner' > "$t/work/rebuild-dev/identity.env"
printf '%s\n' 'ntfy-owner-password=pw1' > "$t/keys/rebuild-secret-source.env"
run put-apps; r9a=$rc o9a=$out c9a=$calls
settings '{"address": "bao-dev.invalid", "sops_copies": true}'
rm -f "$t/keys/rebuild-secret-source.env"; run put-apps; r9b=$rc o9b=$out c9b=$calls
printf '%s\n' 'ntfy-owner-password=pw1' 'Bad_Name=x' > "$t/keys/rebuild-secret-source.env"; run put-apps; r9c=$rc o9c=$out c9c=$calls
printf '%s\n' '# a comment' '' 'ntfy-owner-password=pw1' '  ' 'healthchecks-ping-url=https://hc.invalid/a?b=c' > "$t/keys/rebuild-secret-source.env"
printf '%s' 'ntfy-proxmox-token=tk_last' >> "$t/keys/rebuild-secret-source.env"
mv "$t/work/rebuild-dev/identity.env" "$t/ident.keep"; run put-apps; r9f=$rc o9f=$out c9f=$calls
printf '%s\n' 'GRAFANA_CLIENT_SECRET=g' 'lower_key=x' > "$t/work/rebuild-dev/identity.env"; run put-apps; r9g=$rc o9g=$out c9g=$calls
mv "$t/ident.keep" "$t/work/rebuild-dev/identity.env"
rm -f "$t/kv-log"; run put-apps; r9d=$rc o9d=$out log9d=$(cat "$t/kv-log" 2>/dev/null)
printf '%s\n' 'share-pod-authkey=prodkey' > "$t/keys/prod/secret-source.env"
printf '%s\n' 'ARGOCD_CLIENT_SECRET=a1' > "$t/keys/prod/identity.env"
echo '{"address": "bao-prod.invalid", "sops_copies": true}' > "$t/work/secrets-store-prod.json"
rm -f "$t/keys/prod/cloudflare-dns01-token.txt"; run --prod put-apps; r9h=$rc o9h=$out c9h=$calls
printf '  \n' > "$t/keys/prod/cloudflare-dns01-token.txt"; run --prod put-apps; r9i=$rc o9i=$out c9i=$calls
printf '  cf-token-1\n\n' > "$t/keys/prod/cloudflare-dns01-token.txt"
rm -f "$t/kv-log"; run --prod put-apps; r9e=$rc o9e=$out log9e=$(cat "$t/kv-log" 2>/dev/null)
want9d="c1/ntfy-owner-password value [pw1]"$'\n'"c1/healthchecks-ping-url value [https://hc.invalid/a?b=c]"$'\n'"c1/ntfy-proxmox-token value [tk_last]"
want9d+=$'\n'"c1/identity GRAFANA_CLIENT_SECRET [g=1]"$'\n'"c1/identity PASSWORD_OWNER [pw-owner]"
want9e="c1/share-pod-authkey value [prodkey]"$'\n'"c1/identity ARGOCD_CLIENT_SECRET [a1]"$'\n'"c1/cloudflare-api-token value [cf-token-1]"
if [[ $r9a -ne 0 && $o9a == *"wait for the owner's tap"* && -z $c9a && $r9b -ne 0 && $o9b == *"is missing or empty"* && -z $c9b &&
      $r9c -ne 0 && $o9c == *"not <name>=<value>"* && -z $c9c && $r9d -eq 0 && $log9d == "$want9d" &&
      $o9d == *"put-apps: 3 values from rebuild-secret-source.env at c1/<name> key value, 2 from identity.env at c1/identity"* &&
      $o9d != *pw1* && $o9d != *tk_last* && $o9d != *pw-owner* && $o9d != *"DNS-01"* &&
      $r9f -ne 0 && $o9f == *"identity.env is missing or empty"* && -z $c9f &&
      $r9g -ne 0 && $o9g == *"not KEY=<value>"* && -z $c9g &&
      $r9h -ne 0 && $o9h == *"cloudflare-dns01-token.txt is missing or empty"* && -z $c9h &&
      $r9i -ne 0 && $o9i == *"holds no single token"* && -z $c9i &&
      $r9e -eq 0 && $log9e == "$want9e" && $o9e == *"and the DNS-01 token at c1/cloudflare-api-token"* && $o9e != *cf-token-1* ]]; then
  ok "9. put-apps: refused without sops_copies, a file or good lines; otherwise each line as put c1/<name> value, each identity line as put c1/identity KEY, and on prod the trimmed DNS-01 token, value on stdin"
else bad "9. $r9a $o9a | $r9b $o9b | $r9c $o9c | $r9d [$log9d] $o9d | $r9f $o9f | $r9g $o9g | $r9h $o9h | $r9i $o9i | $r9e [$log9e] $o9e"; fi

# 10
# Dev's address comes from the rebuild's copy of the dev inventory, never from the settings.
rm -f "$dev_inv"
settings '{"address": "bao-dev.invalid", "sops_copies": true, "admin_address": "192.0.2.49"}'
run status; r10f=$rc o10f=$out c10f=$calls
admin_copy
run status; r10a=$rc c10a=$calls
run put c1/app/db password < <(printf v); r10b=$rc k10b=$(cat "$t/kv-resolve")
printf '%s\n' "all:" "  vars:" "    k8s_gitops_source_openbao_admin_address: bao-admin.invalid" > "$dev_inv"
run status; r10c=$rc o10c=$out c10c=$calls
admin_copy
prod_inv=("all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_gitops_source_openbao_store_host: bao-prod.invalid")
echo '{"address": "bao-prod.invalid"}' > "$t/work/secrets-store-prod.json"
printf '%s\n' "${prod_inv[@]}" "        k8s_gitops_source_openbao_admin_address: 192.0.2.41" > "$t/work/openbao-prod/inventory/hosts.yml"
run --prod status; r10d=$rc c10d=$calls
printf '%s\n' "${prod_inv[@]}" "        k8s_gitops_source_openbao_admin_address: 192.0.2.41" "    k8s_workers:" "      vars:" \
  "        k8s_gitops_source_openbao_admin_address: 192.0.2.42" > "$t/work/openbao-prod/inventory/hosts.yml"
run --prod status; r10e=$rc o10e=$out c10e=$calls
printf '%s\n' "${prod_inv[@]}" "$prod_admin" > "$t/work/openbao-prod/inventory/hosts.yml"
settings '{"address": "bao-dev.invalid"}'
if [[ $r10f -ne 0 && $o10f == *"the dev store has no admin address"* && -z $c10f && $o10f != *192.0.2.49* &&
      $r10a -eq 0 && $c10a == *"--resolve bao-dev.invalid:443:192.0.2.40 "*"https://bao-dev.invalid/v1/sys/health"* && $c10a != *192.0.2.10* &&
      $r10b -eq 0 && $k10b == bao-dev.invalid:443:192.0.2.40 &&
      $r10c -ne 0 && $o10c == *"admin address is not one IPv4 address"* && -z $c10c &&
      $r10d -eq 0 && $c10d == *"--resolve bao-prod.invalid:443:192.0.2.41 "*"https://bao-prod.invalid/v1/sys/health"* &&
      $r10e -ne 0 && $o10e == *"gives two admin addresses"* && -z $c10e ]]; then
  ok "10. the admin address: dev's from the rebuild's inventory copy (not the settings: alone, refused), prod's from its inventory, every call there by name; not IPv4 or two: refused"
else bad "10. $r10f $o10f [$c10f] | $r10a [$c10a] | $r10b [$k10b] | $r10c $o10c | $r10d [$c10d] | $r10e $o10e"; fi

# 11
settings '{"address": "bao-dev.invalid", "sops_copies": true}'
date -u > "$t/work/state/secrets-store.rebuilding"
run put c1/app/db password < <(printf v); r11a=$rc o11a=$out c11a=$calls
run put-apps; r11b=$rc o11b=$out c11b=$calls
rm -f "$t/work/state/secrets-store.rebuilding"
run put-apps; r11c=$rc
echo '{"address": "bao-prod.invalid", "sops_copies": true}' > "$t/work/secrets-store-prod.json"
date -u > "$t/work/state/secrets-store-prod.rebuilding"
run --prod put-apps; r11d=$rc o11d=$out c11d=$calls
rm -f "$t/work/state/secrets-store-prod.rebuilding"
run --prod put-apps; r11e=$rc
if [[ $r11a -ne 0 && $o11a == *"a rebuild is in progress"*"nothing written"* && -z $c11a &&
      $r11b -ne 0 && $o11b == *"a rebuild is in progress"*"nothing written"* && -z $c11b && $r11c -eq 0 &&
      $r11d -ne 0 && $o11d == *"secrets-store-prod.rebuilding"* && -z $c11d && $r11e -eq 0 ]]; then
  ok "11. put and put-apps write nothing during a rebuild hold, dev and prod; without it they run"
else bad "11. $r11a $o11a [$c11a] | $r11b $o11b [$c11b] | $r11c | $r11d $o11d [$c11d] | $r11e"; fi

exit $fail
