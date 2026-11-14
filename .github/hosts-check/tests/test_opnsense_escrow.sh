#!/usr/bin/env bash
# The off-box OPNsense copy's password escrow (hosts/ansible/roles/agent_box/files/opnsense-escrow.py, pick 222),
# against the stand-in for Entra ID and Key Vault (azure_stub.py), which refuses to return a value as the box's
# set-only role does:
#   1. ensure makes a 0600 password and writes it to the vault as a version tagged with its SHA-256.
#   2. A second ensure finds the tag current and writes nothing.
#   3. A newer version holding another password (the tag differs) makes ensure write the current one again.
#   4. A refused set fails ensure, and the password file stays as it was.
#   5. A certificate the stand-in does not know fails ensure before any write.
#   6. The value never appears in what ensure prints.
# Usage: .github/hosts-check/tests/test_opnsense_escrow.sh   (needs python3, openssl)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
here=$root/.github/hosts-check/tests
work=$(mktemp -d)
stub_pid=
trap '[ -n "$stub_pid" ] && kill "$stub_pid" 2>/dev/null; rm -rf "$work"' EXIT

# The box's layout: both scripts side by side, as the role installs them.
mkdir -p "$work/libexec" "$work/keys"
cp "$root/hosts/ansible/roles/k8s_backup/files/c1-backup-azure-cert.py" "$work/libexec/azure-cert.py"
cp "$root/hosts/ansible/roles/agent_box/files/opnsense-escrow.py" "$work/libexec/opnsense-escrow.py"

tenant=22222222-2222-2222-2222-222222222222
client=33333333-3333-3333-3333-333333333333
object=44444444-4444-4444-4444-444444444444
echo '{"keys": {}, "tokens": [], "calls": []}' > "$work/state.json"
python3 "$here/azure_stub.py" "$work/port" "$work/state.json" "$tenant" "$client" "$object" &
stub_pid=$!
for _ in $(seq 50); do [ -s "$work/port" ] && break; sleep 0.1; done
port=$(cat "$work/port")

cat > "$work/keys/settings.env" <<ENV
AZURE_CLIENT_ID=$client
AZURE_TENANT_ID=$tenant
AZURE_APP_OBJECT_ID=$object
AZURE_CLIENT_CERTIFICATE_PATH=$work/keys/azure.pem
RESTIC_PASSWORD_FILE=$work/keys/restic-password.txt
OFFBOX_VAULT_URL=http://127.0.0.1:$port
OFFBOX_VAULT_SECRET=opnsense-offbox-restic-password
ENV
while read -r name; do unset "$name"; done < <(env | sed -n 's/^\(\(AZURE\|BACKUP\)_[A-Z_]*\)=.*/\1/p')
export CENTRAL_HUB_BACKUP_ENV=$work/keys/settings.env
export AZURE_AUTHORITY_HOST=http://127.0.0.1:$port

fail() { echo "FAIL: $*" >&2; exit 1; }
state() { python3 -c "import json,sys; s=json.load(open('$work/state.json')); print(eval(sys.argv[1]))" "$1"; }
escrow() { python3 "$work/libexec/opnsense-escrow.py" ensure; }

# The box's certificate, registered as the role's first upload does.
python3 "$work/libexec/azure-cert.py" init > "$work/init.json"
python3 - "$work/init.json" "$work/state.json" <<'PY'
import json, sys
cert = json.load(open(sys.argv[1]))["certificate"]
der = "".join(l for l in cert.splitlines() if "-----" not in l)
s = json.load(open(sys.argv[2])); s["keys"]["k1"] = der
json.dump(s, open(sys.argv[2], "w"))
PY

# 1
out=$(escrow 2>&1) || fail "first ensure: $out"
pw=$work/keys/restic-password.txt
[ "$(stat -c %a "$pw")" = 600 ] || fail "password file mode is $(stat -c %a "$pw")"
value=$(tr -d '\n' < "$pw")
[ ${#value} -ge 32 ] || fail "password is too short"
[ "$(state 'len(s["secrets"]["opnsense-offbox-restic-password"])')" = 1 ] || fail "no version written"
[ "$(state 's["secrets"]["opnsense-offbox-restic-password"][0]["value"]')" = "$value" ] || fail "the vault holds another value"
want=$(printf '%s' "$value" | sha256sum | cut -d' ' -f1)
[ "$(state 's["secrets"]["opnsense-offbox-restic-password"][0]["tags"]["sha256"]')" = "$want" ] || fail "the version's sha256 tag is wrong"
[[ $out == *"made a new repository password"* && $out == *"wrote the current password"* ]] || fail "first ensure said: $out"
[[ $out != *"$value"* ]] || fail "the value was printed"
echo "ok   1. ensure makes a 0600 password and writes one tagged version"

# 2
out=$(escrow 2>&1) || fail "second ensure: $out"
[ "$(state 'len(s["secrets"]["opnsense-offbox-restic-password"])')" = 1 ] || fail "a current tag still wrote a version"
[[ $out == *"holds the current password"* ]] || fail "second ensure said: $out"
[ "$(tr -d '\n' < "$pw")" = "$value" ] || fail "the password changed"
echo "ok   2. a current tag writes nothing, and the password stays"

# 3
python3 - "$work/state.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
v = s["secrets"]["opnsense-offbox-restic-password"]
v.append({"value": "other", "tags": {"sha256": "0" * 64}, "created": max(x["created"] for x in v) + 1, "enabled": True})
json.dump(s, open(sys.argv[1], "w"))
PY
out=$(escrow 2>&1) || fail "ensure after a foreign version: $out"
[ "$(state 'len(s["secrets"]["opnsense-offbox-restic-password"])')" = 3 ] || fail "a foreign newest version was not replaced"
echo "ok   3. a newer version with another password is replaced by the current one"

# 4
python3 -c "import json,sys; s=json.load(open(sys.argv[1])); s['reject_setsecret']=True; s['secrets']={}; json.dump(s,open(sys.argv[1],'w'))" "$work/state.json"
if out=$(escrow 2>&1); then fail "a refused set passed: $out"; fi
[[ $out == *"setting the secret answered 403"* ]] || fail "refused set said: $out"
[ "$(tr -d '\n' < "$pw")" = "$value" ] || fail "a refused set changed the password file"
echo "ok   4. a refused set fails, and the password file stays"

# 5
python3 -c "import json,sys; s=json.load(open(sys.argv[1])); s['reject_setsecret']=False; s['keys']={}; s['calls']=[]; json.dump(s,open(sys.argv[1],'w'))" "$work/state.json"
if out=$(escrow 2>&1); then fail "an unknown certificate passed: $out"; fi
[[ $out == *"no Key Vault token"* ]] || fail "unknown certificate said: $out"
[ "$(state 'len([c for c in s["calls"] if c.startswith("PUT")])')" = 0 ] || fail "an unknown certificate still wrote"
echo "ok   5. an unknown certificate fails before any write"
echo "ok   6. the value was never printed"
