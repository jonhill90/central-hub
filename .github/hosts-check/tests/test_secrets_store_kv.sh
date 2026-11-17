#!/usr/bin/env bash
# The secrets-store wrapper's SOPS copies (hosts/ansible/roles/agent_box/files/secrets-store-kv.sh, D-0058 rule 8),
# with the real SOPS and age and a stand-in OpenBao (a stub curl that keeps KV v2 in a JSON file, with check-and-set):
#   1. put makes the SOPS file for the box's identity, writes the one key there, then to OpenBao.
#   2. A second key at the same path is merged in both, and the OpenBao write carries the version it read (cas).
#   3. A value with quotes, a backslash, newlines and non-ASCII text comes back the same from SOPS and from OpenBao.
#   4. No value, token or AppRole ID is in any argument of curl, sops, age-keygen or python3, or in the output.
#   5. Order: a failed SOPS write leaves OpenBao untouched; a failed sign-in or a refused OpenBao write after it says
#      SOPS is written and OpenBao is not; a write in between (the version moved) is refused, not overwritten.
#   6. compare passes when both hold the same; it names a changed key, a key only in OpenBao and a key only in SOPS,
#      by path and name only, and exits 1.
#   7. reseed refuses a store that holds anything but c1/check and writes nothing; into a fresh store it writes every
#      path, and compare then passes.
#   8. A path outside c1/, a bad key name and an empty value are refused before anything is written.
# SOPS and age come from their GitHub releases, checked against the SHA-256s the role installs.
# Usage: .github/hosts-check/tests/test_secrets_store_kv.sh   (needs curl, python3 with PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
role=$root/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
def() { python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))[sys.argv[2]])' "$role/defaults/main.yml" "$1"; }
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/real" "$t/libexec" "$t/bin" "$t/keys/dev" "$t/keys/secrets-bundle"
sv=$(def agent_box_sops_version)
curl -sSLf --retry 5 --retry-delay 10 -o "$t/real/sops" "https://github.com/getsops/sops/releases/download/v$sv/sops-v$sv.linux.amd64"
echo "$(def agent_box_sops_sha256)  $t/real/sops" | sha256sum -c --quiet || exit 1
av=$(def agent_box_age_version)
curl -sSLf --retry 5 --retry-delay 10 -o "$t/age.tgz" "https://github.com/FiloSottile/age/releases/download/v$av/age-v$av-linux-amd64.tar.gz"
echo "$(def agent_box_age_sha256)  $t/age.tgz" | sha256sum -c --quiet || exit 1
tar -xzf "$t/age.tgz" -C "$t" age/age-keygen && mv "$t/age/age-keygen" "$t/real/age-keygen"
chmod +x "$t/real/"*
"$t/real/age-keygen" -o "$t/keys/secrets-bundle/age-identity.txt" 2>/dev/null

# Every program the helper runs logs its arguments, one line per call, then runs the real one.
py=$(command -v python3)
for p in sops age-keygen; do
  printf '#!/bin/bash\nprintf "%%s\\n" "%s $*" >> %s/args\nexec %s/real/%s "$@"\n' "$p" "$t" "$t" "$p" > "$t/libexec/$p"
done
printf '#!/bin/bash\nprintf "%%s\\n" "python3 $*" >> %s/args\nexec %s "$@"\n' "$t" "$py" > "$t/bin/python3"

# OpenBao: KV v2 in $t/store.json ({"path": {"version": n, "data": {...}}}). The token must come on stdin as a header.
rid=0123456789abcdef0123456789abcdef0123456789abcdef
sid=fedcba9876543210fedcba9876543210fedcba9876543210
printf '%s' "$rid" > "$t/keys/dev/openbao-admin-role-id"
printf '%s' "$sid" > "$t/keys/dev/openbao-admin-secret-id"
cat > "$t/bin/curl" <<EOF
#!$py -I
import json, os, sys
args = sys.argv[1:]
with open("$t/args", "a") as f: f.write("curl " + " ".join(args) + "\n")
with open("$t/calls", "a") as f: pass
method, out, fmt, body, hdr_stdin, url = "GET", None, None, None, False, None
i = 0
while i < len(args):
    a = args[i]
    if a == "-X": method = args[i + 1]; i += 2; continue
    if a == "-o": out = args[i + 1]; i += 2; continue
    if a == "-w": fmt = args[i + 1]; i += 2; continue
    if a == "--cacert": i += 2; continue
    if a == "-H" and args[i + 1] == "@-": hdr_stdin = True; i += 2; continue
    if a in ("--data", "--data-binary"):
        v = args[i + 1]
        body = sys.stdin.read() if v == "@-" else open(v[1:]).read() if v.startswith("@") else v
        i += 2; continue
    if a == "-s": i += 1; continue
    url = a; i += 1
path = url.split("/v1/", 1)[1]
token = None
if hdr_stdin:
    line = sys.stdin.read().strip()
    if line.startswith("X-Vault-Token: "): token = line[len("X-Vault-Token: "):]
sf = "$t/store.json"
store = json.load(open(sf)) if os.path.exists(sf) else {}
mode = os.environ.get("BAO", "ok")
with open("$t/calls", "a") as f: f.write("%s %s\n" % (method, path))
def reply(code, obj=None):
    text = json.dumps(obj) if obj is not None else ""
    if out: open(out, "w").write(text)
    else: sys.stdout.write(text)
    if fmt: sys.stdout.write(fmt.replace("%{http_code}", str(code)).replace("\\\\n", "\n"))
    sys.exit(0)
if path == "auth/approle/login":
    b = json.loads(body)
    if mode == "nologin" or b != {"role_id": "$rid", "secret_id": "$sid"}: reply(400, {"errors": ["invalid"]})
    reply(200, {"auth": {"client_token": "tok-secret-1"}})
if token != "tok-secret-1": reply(403, {"errors": ["permission denied"]})
if path == "auth/token/revoke-self": reply(204)
if path.startswith("kv/data/"):
    p = path[len("kv/data/"):]
    if method == "GET":
        if p not in store: reply(404, {"errors": []})
        v = store[p]["version"]
        if mode == "race":   # someone else writes between this read and the write
            store[p]["version"] = v + 1; json.dump(store, open(sf, "w"))
        reply(200, {"data": {"data": store[p]["data"], "metadata": {"version": v}}})
    if method == "POST":
        if mode == "refuse": reply(500, {"errors": ["refused"]})
        b = json.loads(body)
        cur = store.get(p, {"version": 0})["version"]
        if b["options"]["cas"] != cur: reply(400, {"errors": ["check-and-set parameter did not match the current version"]})
        store[p] = {"version": cur + 1, "data": b["data"]}
        json.dump(store, open(sf, "w"))
        reply(200, {"data": {"version": cur + 1}})
if path.startswith("kv/metadata/") and method == "LIST":
    pre = path[len("kv/metadata/"):]
    keys = set()
    for k in store:
        if k.startswith(pre):
            rest = k[len(pre):]
            keys.add(rest.split("/", 1)[0] + "/" if "/" in rest else rest)
    if not keys: reply(404, {"errors": []})
    reply(200, {"data": {"keys": sorted(keys)}})
reply(405, {"errors": ["unexpected"]})
EOF
chmod +x "$t/libexec/"* "$t/bin/"*

kv() { # action [path key], value on stdin
  PATH="$t/bin:$PATH" bash "$role/files/secrets-store-kv.sh" "$1" https://store.invalid "$t/ca.crt" "$t/keys/dev" "$t/libexec" "${@:2}" > "$t/out" 2>&1
  rc=$?; out=$(cat "$t/out"); all+=$out$'\n'
}
plain() { SOPS_AGE_KEY_FILE=$t/keys/secrets-bundle/age-identity.txt "$t/real/sops" decrypt --input-type json --output-type json "$t/keys/dev/openbao-kv.sops.json"; }
sops_val() { plain | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.stdout.write(d[sys.argv[1]][sys.argv[2]])' "$1" "$2"; }
bao_val() { python3 -c 'import json,sys; sys.stdout.write(json.load(open(sys.argv[1]))[sys.argv[2]]["data"][sys.argv[3]])' "$t/store.json" "$1" "$2"; }
bao_ver() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["version"])' "$t/store.json" "$1"; }
all=""
v1='first-value-Zq81x'
v2='second-value-Kp27w'
v3=$'quote " backslash \\ line\nnext line, café ✓ Wv93m'

# 1
kv put c1/app/db password < <(printf '%s' "$v1")
if [[ $rc -eq 0 && $out == *"kv/c1/app/db key password written to SOPS, then OpenBao"* && -s $t/keys/dev/openbao-kv.sops.json &&
      $(sops_val c1/app/db password) == "$v1" && $(bao_val c1/app/db password) == "$v1" ]] &&
   [[ $(grep -c '^POST kv/data/c1/app/db' "$t/calls") == 1 ]] && ! grep -q "$v1" "$t/keys/dev/openbao-kv.sops.json"; then
  ok "1. put makes the SOPS file, writes the key there, then to OpenBao"
else bad "1. rc=$rc $out"; fi

# 2
kv put c1/app/db user < <(printf '%s' "$v2")
if [[ $rc -eq 0 && $(sops_val c1/app/db password) == "$v1" && $(sops_val c1/app/db user) == "$v2" &&
      $(bao_val c1/app/db password) == "$v1" && $(bao_val c1/app/db user) == "$v2" && $(bao_ver c1/app/db) == 2 ]]; then
  ok "2. a second key at the same path is merged in both, written with the version read"
else bad "2. rc=$rc $out"; fi

# 3
kv put c1/other api_key < <(printf '%s' "$v3")
if [[ $rc -eq 0 && "$(sops_val c1/other api_key)" == "$v3" && "$(bao_val c1/other api_key)" == "$v3" ]]; then
  ok "3. quotes, a backslash, newlines and non-ASCII text come back the same from SOPS and OpenBao"
else bad "3. rc=$rc $out"; fi

# 5
cp "$t/store.json" "$t/store.before"
cp "$t/keys/dev/openbao-kv.sops.json" "$t/sops.before"
mv "$t/keys/secrets-bundle/age-identity.txt" "$t/identity.away"
"$t/real/age-keygen" -o "$t/keys/secrets-bundle/age-identity.txt" 2>/dev/null   # another identity: SOPS can't open the file
: > "$t/calls"
kv put c1/app/db password < <(printf '%s' fifth-value-Rb44t)
r5a=$rc o5a=$out c5a=$(cat "$t/calls")
s5a=same; cmp -s "$t/sops.before" "$t/keys/dev/openbao-kv.sops.json" || s5a=changed
mv "$t/identity.away" "$t/keys/secrets-bundle/age-identity.txt"
BAO=nologin kv put c1/app/db password < <(printf '%s' fifth-value-Rb44t)
r5b=$rc o5b=$out
BAO=refuse kv put c1/app/db password < <(printf '%s' fifth-value-Rb44t)
r5c=$rc o5c=$out
BAO=race kv put c1/app/db password < <(printf '%s' fifth-value-Rb44t)
r5d=$rc o5d=$out
if [[ $r5a -ne 0 && $o5a == *"the SOPS write failed; OpenBao was not written"* && -z $c5a && $s5a == same ]] &&
   [[ $r5b -ne 0 && $o5b == *"SOPS is written, but the admin AppRole did not sign in, so OpenBao is not"* ]] &&
   [[ $r5c -ne 0 && $o5c == *"SOPS is written, but OpenBao refused the write (HTTP 500)"* ]] &&
   [[ $r5d -ne 0 && $o5d == *"OpenBao refused the write (HTTP 400)"* && $(bao_val c1/app/db password) == "$v1" ]]; then
  ok "5. order: a failed SOPS write leaves OpenBao alone; a failed sign-in or refused write names which; a write in between is refused"
else bad "5. $r5a/$r5b/$r5c/$r5d $s5a | $o5a | $o5b | $o5c | $o5d | calls: $c5a"; fi
# Put SOPS and OpenBao back as they were before 5 (the failed puts left SOPS ahead, as their messages say).
cp "$t/sops.before" "$t/keys/dev/openbao-kv.sops.json"
cp "$t/store.before" "$t/store.json"

# 6
kv compare </dev/null
r6a=$rc o6a=$out
python3 - "$t/store.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s["c1/app/db"]["data"]["password"] = "changed-in-bao-Jt55v"
s["c1/other"]["data"]["extra"] = "only-in-bao-Hn66c"
del s["c1/app/db"]["data"]["user"]
json.dump(s, open(sys.argv[1], "w"))
PY
kv compare </dev/null
r6b=$rc o6b=$out
if [[ $r6a -eq 0 && $o6a == *"PASS: compare: 3 keys equal in SOPS and OpenBao"* &&
      $r6b -ne 0 && $o6b == *"DIFF: c1/app/db password differs"* && $o6b == *"DIFF: c1/app/db user is in SOPS, not in OpenBao"* &&
      $o6b == *"DIFF: c1/other extra is in OpenBao, not in SOPS"* && $o6b == *"FAIL: SOPS and OpenBao differ"* &&
      $o6b != *changed-in-bao* && $o6b != *only-in-bao* ]]; then
  ok "6. compare passes when equal, and names each differing key by path and name only"
else bad "6. $r6a/$r6b | $o6a | $o6b"; fi

# 7
: > "$t/calls"
kv reseed </dev/null
r7a=$rc o7a=$out c7a=$(cat "$t/calls")
echo '{"c1/check": {"version": 1, "data": {"word": "check"}}}' > "$t/store.json"
kv reseed </dev/null
r7b=$rc o7b=$out
kv compare </dev/null
if [[ $r7a -ne 0 && $o7a == *"so it is not fresh; nothing written"* && $c7a == *LIST* && $c7a != *"POST kv/data"* ]] &&
   [[ $r7b -eq 0 && $o7b == *"PASS: reseed: 2 paths written from SOPS into the fresh store"* && $rc -eq 0 && $out == *"PASS: compare: 3 keys equal"* ]]; then
  ok "7. reseed refuses a store that is not fresh; into a fresh one it writes every path, and compare passes"
else bad "7. $r7a/$r7b | $o7a | $o7b | $out"; fi

# 8
cp "$t/keys/dev/openbao-kv.sops.json" "$t/sops.before"
: > "$t/calls"
kv put kv/dev/snapshot-mark taken < <(printf x); r8a=$rc
kv put c1/app 'bad key' < <(printf x); r8b=$rc
kv put c1/app key < <(printf ''); r8c=$rc o8c=$out
if [[ $r8a -ne 0 && $r8b -ne 0 && $r8c -ne 0 && $o8c == *"no value on stdin; nothing written"* && ! -s $t/calls ]] &&
   cmp -s "$t/sops.before" "$t/keys/dev/openbao-kv.sops.json"; then
  ok "8. a path outside c1/, a bad key and an empty value are refused before anything is written"
else bad "8. $r8a/$r8b/$r8c $o8c"; fi

# 4 (over every run above)
leak=0
for s in "$v1" "$v2" first-value second-value Wv93m fifth-value tok-secret-1 "$rid" "$sid" changed-in-bao only-in-bao; do
  if grep -qF -- "$s" "$t/args"; then echo "     in an argument: $s"; leak=1; fi
  if [[ $all == *"$s"* ]]; then echo "     in the output: $s"; leak=1; fi
done
if [[ $leak -eq 0 ]] && grep -q '^sops set --value-stdin' "$t/args" && grep -q '^curl ' "$t/args"; then
  ok "4. no value, token or AppRole ID in any argument of curl, sops, age-keygen or python3, or in the output"
else bad "4. a value, token or ID leaked (above)"; fi

exit $fail
