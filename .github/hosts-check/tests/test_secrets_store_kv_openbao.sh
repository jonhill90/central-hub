#!/usr/bin/env bash
# The secrets-store wrapper's SOPS copies (hosts/ansible/roles/agent_box/files/secrets-store-kv.sh, D-0058 rule 8)
# against a real OpenBao: the server at the version apps/openbao pins, in dev mode with TLS, set up the way the chart's
# self-init sets up the store (apps/openbao/values.yaml): KV v2 at kv/, the AppRole login, the chart's own policy
# files, role admin with policy admin and its /32 bindings, a custom secret ID as the hand-over writes it, and the
# word ok at kv/data/c1/check. test_secrets_store_kv.sh covers the same helper against a stand-in; this one proves the
# stand-in's answers are OpenBao's:
#   1. put signs in as the admin AppRole, makes the SOPS file, and writes a new path with cas 0; a second key at the
#      same path merges with cas 1. OpenBao then holds both keys, byte for byte (quotes, a backslash, newlines,
#      non-ASCII), at version 2.
#   2. compare passes; after a write outside put (the root token), it names that key only and exits 1.
#   3. A check-and-set on a version that is no longer current is refused by OpenBao (the guard put relies on).
#   4. reseed refuses a store that holds more than c1/check and dev/snapshot-mark and writes nothing; into a fresh
#      store with both, it writes every path, and compare then passes.
#   5. The admin policy is enough for put, compare and reseed (each above signs in as admin only), the admin token is
#      revoked when the helper ends, and policy eso-c1 reads the paths put writes and nothing outside c1/.
#   6. No value is in the helper's output.
# Usage: .github/hosts-check/tests/test_secrets_store_kv_openbao.sh   (needs curl, python3 with PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
role=$root/hosts/ansible/roles/agent_box
apps=$root/hosts/kubernetes/home/c1/apps
t=$(mktemp -d)
pid=''
trap '[[ -z $pid ]] || kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT
def() { python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))[sys.argv[2]])' "$role/defaults/main.yml" "$1"; }
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

# OpenBao: the version apps/openbao pins (its image tag), and the SHA-256 of that release's linux amd64 archive,
# from the release's checksums.txt (https://github.com/openbao/openbao/releases/tag/v2.7.2).
bao_version=2.7.2
bao_sha256=582b1f3c2fdc5afd443b2d57a225ef654de75adea609fdb66731fd582a9cbc96
pinned=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["server"]["image"]["tag"].split("@")[0])' "$apps/openbao/values.yaml")
[[ $pinned == "$bao_version" ]] || { echo "FAIL apps/openbao pins $pinned, this test $bao_version: update both together"; exit 1; }

mkdir -p "$t/real" "$t/libexec" "$t/keys/dev" "$t/keys/secrets-bundle" "$t/tls"
curl -sSLf --retry 5 --retry-delay 10 -o "$t/bao.tgz" "https://github.com/openbao/openbao/releases/download/v$bao_version/openbao_${bao_version}_linux_amd64.tar.gz"
echo "$bao_sha256  $t/bao.tgz" | sha256sum -c --quiet || exit 1
tar -xzf "$t/bao.tgz" -C "$t/real" bao
sv=$(def agent_box_sops_version)
curl -sSLf --retry 5 --retry-delay 10 -o "$t/libexec/sops" "https://github.com/getsops/sops/releases/download/v$sv/sops-v$sv.linux.amd64"
echo "$(def agent_box_sops_sha256)  $t/libexec/sops" | sha256sum -c --quiet || exit 1
av=$(def agent_box_age_version)
curl -sSLf --retry 5 --retry-delay 10 -o "$t/age.tgz" "https://github.com/FiloSottile/age/releases/download/v$av/age-v$av-linux-amd64.tar.gz"
echo "$(def agent_box_age_sha256)  $t/age.tgz" | sha256sum -c --quiet || exit 1
tar -xzf "$t/age.tgz" -C "$t" age/age-keygen && mv "$t/age/age-keygen" "$t/libexec/age-keygen"
chmod +x "$t/real/bao" "$t/libexec/"*
"$t/libexec/age-keygen" -o "$t/keys/secrets-bundle/age-identity.txt" 2>/dev/null

port=$((20000 + RANDOM % 20000))
addr=https://127.0.0.1:$port
export BAO_ADDR=$addr BAO_CACERT=$t/tls/vault-ca.pem
roottoken=root-$RANDOM$RANDOM
bao() { BAO_TOKEN=$roottoken "$t/real/bao" "$@"; }
rid=0123456789abcdef0123456789abcdef0123456789abcdef
sid=fedcba9876543210fedcba9876543210fedcba9876543210
printf '%s' "$rid" > "$t/keys/dev/openbao-admin-role-id"
printf '%s' "$sid" > "$t/keys/dev/openbao-admin-secret-id"

# A fresh store, set up as the chart's self-init and the hand-over set it up.
start() {
  [[ -z $pid ]] || { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
  rm -rf "$t/tls"/*
  "$t/real/bao" server -dev -dev-tls -dev-tls-cert-dir="$t/tls" -dev-root-token-id="$roottoken" \
    -dev-listen-address="127.0.0.1:$port" > "$t/server.log" 2>&1 &
  pid=$!
  for _ in $(seq 1 50); do [[ -s $t/tls/vault-ca.pem ]] && bao status >/dev/null 2>&1 && break; sleep 0.2; done
  bao status >/dev/null 2>&1 || { echo "FAIL OpenBao did not start"; cat "$t/server.log"; exit 1; }
  bao secrets enable -path=kv -version=2 kv >/dev/null &&
    bao auth enable approle >/dev/null &&
    bao policy write admin "$apps/openbao-store/policies/admin.hcl" >/dev/null &&
    bao policy write eso-c1 "$apps/openbao-store/policies/eso-c1.hcl" >/dev/null &&
    bao write auth/approle/role/admin token_policies=admin token_ttl=15m token_max_ttl=1h \
      secret_id_bound_cidrs=127.0.0.1/32 token_bound_cidrs=127.0.0.1/32 >/dev/null &&
    printf '{"role_id":"%s"}' "$rid" | bao write auth/approle/role/admin/role-id - >/dev/null &&
    printf '{"secret_id":"%s"}' "$sid" | bao write auth/approle/role/admin/custom-secret-id - >/dev/null &&
    bao kv put -mount=kv c1/check value=ok >/dev/null ||
    { echo "FAIL the store's setup failed"; cat "$t/server.log"; exit 1; }
}
kv() { bash "$role/files/secrets-store-kv.sh" "$1" "$addr" "$t/tls/vault-ca.pem" "$t/keys/dev" "$t/libexec" "${@:2}"; }
read_kv() { bao kv get -mount=kv -format=json "$1" | python3 -I -c 'import json,sys; d=json.load(sys.stdin)["data"]; print(json.dumps({"version": d["metadata"]["version"], "data": d["data"]}))'; }

start
odd=$'quote " backslash \\ line\nnext line\n\xc3\xa9t\xc3\xa9 \xe2\x82\xac'
# 1. put: a new path, then a second key at the same path.
out1=$(printf '%s' "$odd" | kv put c1/app-one password 2>&1); rc1=$?
out2=$(printf '%s' "second" | kv put c1/app-one token 2>&1); rc2=$?
if [[ $rc1 == 0 && $rc2 == 0 && $out1 == *"written to SOPS, then OpenBao"* && $out2 == *"written to SOPS, then OpenBao"* ]]; then
  ok "put signs in as admin and writes a new path, then a second key at it"
else bad "put failed: $out1 / $out2"; fi
read_kv c1/app-one > "$t/one.json"
python3 -I - "$t/one.json" "$odd" <<'PY' && ok "OpenBao holds both keys byte for byte, at version 2 (cas 0, then cas 1)" || bad "OpenBao does not hold what put wrote"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["version"] == 2, d["version"]
assert d["data"] == {"password": sys.argv[2], "token": "second"}, sorted(d["data"])
PY
SOPS_AGE_KEY_FILE=$t/keys/secrets-bundle/age-identity.txt "$t/libexec/sops" decrypt --input-type json --output-type json "$t/keys/dev/openbao-kv.sops.json" > "$t/plain.json"
python3 -I - "$t/plain.json" "$odd" <<'PY' && ok "the SOPS file holds the same two keys" || bad "the SOPS file does not hold what put wrote"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["c1/app-one"] == {"password": sys.argv[2], "token": "second"}, d.keys()
PY
printf '%s' "x" | kv put c1/app-two value >/dev/null 2>&1 || bad "put of a second path failed"

# 2. compare.
out=$(kv compare 2>&1) && [[ $out == *"PASS: compare: 3 keys equal in SOPS and OpenBao"* ]] && ok "compare passes on 3 keys" || bad "compare: $out"
bao kv patch -mount=kv c1/app-one token=changed >/dev/null
out=$(kv compare 2>&1); rc=$?
if [[ $rc != 0 && $out == *"DIFF: c1/app-one token differs"* && $out != *password* && $out != *app-two* ]]; then
  ok "after a write outside put, compare names that key only and exits 1"
else bad "compare after an outside write: rc $rc: $out"; fi
printf '%s' "second" | kv put c1/app-one token >/dev/null 2>&1
out=$(kv compare 2>&1) && ok "a put of the right value makes compare pass again" || bad "compare after the fix: $out"

# 3. check-and-set: a write on a version that is no longer current is refused.
v=$(read_kv c1/app-one | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["version"])')
if bao kv put -mount=kv -cas=$((v - 1)) c1/app-one token=late >/dev/null 2>&1; then
  bad "OpenBao took a cas write on version $((v - 1)) while $v is current"
else ok "OpenBao refuses a cas write on a version that is no longer current"; fi

# 4. reseed: refused on a store with data, then into a fresh one.
out=$(kv reseed 2>&1); rc=$?
if [[ $rc != 0 && $out == *"the store holds kv/c1/app-"*"so it is not fresh; nothing written"* ]]; then
  ok "reseed refuses a store that holds data"
else bad "reseed on a store with data: rc $rc: $out"; fi
start
bao kv put -mount=kv dev/snapshot-mark value=2026-11-18T00:00:00Z >/dev/null
out=$(kv reseed 2>&1); rc=$?
[[ $rc == 0 && $out == *"PASS: reseed: 2 paths written from SOPS into the fresh store"* ]] && ok "reseed fills a fresh store that holds only c1/check and the mark" || bad "reseed into a fresh store: rc $rc: $out"
out=$(kv compare 2>&1) && [[ $out == *"PASS: compare: 3 keys equal"* ]] && ok "compare passes after reseed" || bad "compare after reseed: $out"
read_kv c1/app-one > "$t/one.json"
python3 -I - "$t/one.json" "$odd" <<'PY' && ok "the reseeded value is the same byte for byte" || bad "the reseeded value differs"
import json, sys
assert json.load(open(sys.argv[1]))["data"]["password"] == sys.argv[2]
PY

# 5. The admin token is revoked at the end; eso-c1 reads c1/ only.
n=$(bao list -format=json auth/token/accessors | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)))')
[[ $n == 1 ]] && ok "no admin token is left after the helper ends (only the root token's accessor)" || bad "$n token accessors after the helper ended"
eso=$(bao token create -policy=eso-c1 -field=token)
if BAO_TOKEN=$eso "$t/real/bao" kv get -mount=kv -field=token c1/app-one 2>/dev/null | grep -qx second &&
  ! BAO_TOKEN=$eso "$t/real/bao" kv get -mount=kv dev/snapshot-mark >/dev/null 2>&1; then
  ok "eso-c1 reads a path put wrote, and is refused outside c1/"
else bad "eso-c1 does not read c1/ only"; fi

# 6. No value in the helper's output.
if [[ "$out1$out2" == *second* || "$out1$out2" == *backslash* ]]; then bad "a value is in put's output"; else ok "no value is in put's output"; fi

[[ $fail -eq 0 ]] && echo "secrets-store kv against OpenBao $bao_version: all checks passed" || { echo "secrets-store kv against OpenBao: a check failed"; exit 1; }
