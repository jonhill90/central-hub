#!/usr/bin/env bash
# Test of the node's own Azure sign-in for c1's backups (role k8s_backup, c1-backup-azure-cert.py),
# against a stand-in for Entra ID and Microsoft Graph (azure_stub.py) that checks every JWT's
# signature, audience and issuer, so no Azure account is needed:
#   1. init makes a key and certificate in one 0600 file, and a second init leaves it alone.
#   2. check says "not registered" (exit 3) before the first upload, and passes after it.
#   3. renew does nothing while more than BACKUP_CERT_RENEW_DAYS are left.
#   4. renew inside that window adds a new certificate with a valid proof, switches the file, and
#      removes the old certificate from the app; the new one signs in.
#   5. a refused addKey fails the run and leaves the current file in use.
#   6. a missing file fails renew with a clear error.
#   7. role tasks azure_identity.yml, with a stand-in az, make the file, upload the certificate
#      once, record its key ID, remove an expired certificate, and write the env lines restic reads.
# Usage: .github/hosts-check/tests/test_backup_azure_cert.sh   (needs python3, openssl, ansible-core)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
here=$root/.github/hosts-check/tests
script=$root/hosts/ansible/roles/k8s_backup/files/c1-backup-azure-cert.py
work=$(mktemp -d)
stub_pid=
trap '[ -n "$stub_pid" ] && kill "$stub_pid" 2>/dev/null; rm -rf "$work"' EXIT

tenant=22222222-2222-2222-2222-222222222222
client=33333333-3333-3333-3333-333333333333
object=44444444-4444-4444-4444-444444444444
echo '{"keys": {}, "tokens": [], "calls": []}' > "$work/state.json"
python3 "$here/azure_stub.py" "$work/port" "$work/state.json" "$tenant" "$client" "$object" &
stub_pid=$!
for _ in $(seq 50); do [ -s "$work/port" ] && break; sleep 0.1; done
port=$(cat "$work/port")

fail() { echo "FAIL: $*" >&2; exit 1; }
state() { python3 -c "import json,sys; s=json.load(open('$work/state.json')); print(eval(sys.argv[1]))" "$1"; }

mkdir -p "$work/etc"
cat > "$work/etc/backup.env" <<ENV
AZURE_ACCOUNT_NAME=exampleaccount
AZURE_CLIENT_ID=$client
AZURE_TENANT_ID=$tenant
AZURE_APP_OBJECT_ID=$object
AZURE_CLIENT_CERTIFICATE_PATH=$work/etc/azure/backup.pem
ENV
chmod 0600 "$work/etc/backup.env"
# The environment wins over the env file, so none of the machine's own Azure settings may leak in.
while read -r name; do unset "$name"; done < <(env | sed -n 's/^\(\(AZURE\|BACKUP\)_[A-Z_]*\)=.*/\1/p')
export CENTRAL_HUB_BACKUP_ENV=$work/etc/backup.env
export AZURE_AUTHORITY_HOST=http://127.0.0.1:$port
export BACKUP_GRAPH_ENDPOINT=http://127.0.0.1:$port
export BACKUP_CERT_WAIT_SECONDS=5 BACKUP_CERT_WAIT_STEP=1
pem=$work/etc/azure/backup.pem

# 1
python3 "$script" init > "$work/init1.json"
[ "$(stat -c %a "$pem")" = 600 ] || fail "certificate file mode is $(stat -c %a "$pem")"
grep -q "PRIVATE KEY-----" "$pem" && grep -q "BEGIN CERTIFICATE" "$pem" || fail "file lacks key or certificate"
python3 "$script" init > "$work/init2.json"
python3 - "$work/init1.json" "$work/init2.json" <<'PY' || fail "init output"
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:])
assert a["made"] is True and b["made"] is False, (a["made"], b["made"])
assert a["thumbprint"] == b["thumbprint"] and 88 <= a["days_left"] <= 90, a
assert "PRIVATE" not in a["certificate"] and a["certificate"].startswith("-----BEGIN CERTIFICATE-----")
PY
echo "ok   1. init makes one 0600 key and certificate, and keeps it"

# 2
rc=0; python3 "$script" check > "$work/check.log" 2>&1 || rc=$?
[ "$rc" = 3 ] || { cat "$work/check.log"; fail "check before upload exited $rc, not 3"; }
# The first upload, as the playbook makes it with az: the public certificate only.
first_keyid=11111111-0000-0000-0000-000000000001
python3 - "$work/init1.json" "$work/state.json" "$first_keyid" <<'PY'
import json, sys
cert = json.load(open(sys.argv[1]))["certificate"]
s = json.load(open(sys.argv[2]))
s["keys"][sys.argv[3]] = "".join(cert.splitlines()[1:-1])
json.dump(s, open(sys.argv[2], "w"))
PY
echo "$first_keyid" > "$pem.keyid"
python3 "$script" check > "$work/check.log" 2>&1 || { cat "$work/check.log"; fail "check after upload"; }
echo "ok   2. check: not registered (3) before the upload, accepted after it"

# 3
calls=$(state 'len(s["calls"])')
before=$(sha256sum "$pem")
python3 "$script" renew > "$work/renew.log" 2>&1 || { cat "$work/renew.log"; fail "renew with time left"; }
[ "$(sha256sum "$pem")" = "$before" ] || fail "renew with time left changed the file"
[ "$(state 'len(s["calls"])')" = "$calls" ] || fail "renew with time left called Azure"
echo "ok   3. renew with more than 30 days left does nothing"

# 4
old_thumb=$(python3 -c "import json; print(json.load(open('$work/init1.json'))['thumbprint'])")
BACKUP_CERT_RENEW_DAYS=200 python3 "$script" renew > "$work/renew.log" 2>&1 || { cat "$work/renew.log"; fail "renew in the window"; }
[ "$(sha256sum "$pem")" != "$before" ] || fail "renew did not switch the file"
[ "$(stat -c %a "$pem")" = 600 ] || fail "new file mode"
[ ! -e "$pem.new" ] || fail "renew left $pem.new"
new_keyid=$(cat "$pem.keyid")
[ "$(state 'sorted(s["keys"])')" = "['$new_keyid']" ] || { cat "$work/renew.log"; fail "app keys after renew: $(state 'sorted(s["keys"])')"; }
grep -q "removed the old certificate $old_thumb" "$work/renew.log" || { cat "$work/renew.log"; fail "old certificate not removed"; }
python3 "$script" check > "$work/check.log" 2>&1 || { cat "$work/check.log"; fail "check after renew"; }
echo "ok   4. renew adds a new certificate with a valid proof, switches, and removes the old one"

# 5
python3 - "$work/state.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s["reject_addkey"] = True; json.dump(s, open(sys.argv[1], "w"))
PY
before=$(sha256sum "$pem")
if BACKUP_CERT_RENEW_DAYS=200 python3 "$script" renew > "$work/renew.log" 2>&1; then fail "a refused addKey passed"; fi
grep -q "FAIL: addKey answered 400" "$work/renew.log" || { cat "$work/renew.log"; fail "wrong failure"; }
[ "$(sha256sum "$pem")" = "$before" ] && [ ! -e "$pem.new" ] || fail "a refused addKey changed the file"
python3 "$script" check >/dev/null 2>&1 || fail "check after a refused addKey"
echo "ok   5. a refused addKey fails the run and keeps the current certificate"

# 6
if AZURE_CLIENT_CERTIFICATE_PATH=$work/none.pem python3 "$script" renew > "$work/renew.log" 2>&1; then fail "renew with no file passed"; fi
grep -q "is missing: run the playbook's timers tag" "$work/renew.log" || { cat "$work/renew.log"; fail "wrong failure"; }
echo "ok   6. renew with no certificate file fails with a clear error"

# 7: the role's tasks, with a stand-in az that does what `az ad app credential` does to the stub's
# state. It also holds one expired certificate, which the tasks must remove.
python3 - "$work/state.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s["keys"] = {}; s["reject_addkey"] = False
s["expired"] = {"99999999-0000-0000-0000-000000000009": "2020-01-01T00:00:00Z"}
json.dump(s, open(sys.argv[1], "w"))
PY
cat > "$work/az" <<'AZ'
#!/usr/bin/env python3
import base64, hashlib, json, os, sys, uuid
state_file = os.environ["STUB_STATE"]
s = json.load(open(state_file))
args = sys.argv[1:]
open(state_file + ".az.log", "a").write(" ".join(a if not a.startswith("@") else "@file" for a in args) + "\n")
opt = {args[i]: args[i + 1] for i in range(len(args) - 1) if args[i].startswith("--")}
assert args[:3] == ["ad", "app", "credential"], args
assert opt["--id"] == os.environ["STUB_CLIENT"], opt
if args[3] == "reset":
    assert "--append" in args and "--cert" in opt, args
    pem = open(opt["--cert"][1:]).read()
    assert "PRIVATE" not in pem
    s["keys"][str(uuid.uuid4())] = "".join(pem.strip().splitlines()[1:-1])
elif args[3] == "list":
    assert "--cert" in args
    out = []
    for k, v in s["keys"].items():
        tp = base64.b64encode(hashlib.sha1(base64.b64decode(v)).digest()).decode()
        out.append({"keyId": k, "customKeyIdentifier": tp, "endDateTime": "2099-01-01T00:00:00Z", "type": "AsymmetricX509Cert"})
    for k, end in s.get("expired", {}).items():
        out.append({"keyId": k, "customKeyIdentifier": "AAAA", "endDateTime": end, "type": "AsymmetricX509Cert"})
    print(json.dumps(out))
elif args[3] == "delete":
    assert "--cert" in args
    s["keys"].pop(opt["--key-id"], None)
    s.get("expired", {}).pop(opt["--key-id"], None)
else:
    sys.exit("unexpected az call")
json.dump(s, open(state_file, "w"))
AZ
chmod +x "$work/az"
rm -f "$pem" "$pem.keyid"
cat > "$work/play.yml" <<'PLAY'
- name: Azure identity tasks of k8s_backup
  hosts: localhost
  gather_facts: false
  tasks:
    - name: The role's Azure identity tasks
      ansible.builtin.include_role:
        name: k8s_backup
        tasks_from: azure_identity.yml
    - name: Write the env lines for the test to read
      ansible.builtin.copy:
        content: "{{ k8s_backup_azure_env_lines }}"
        dest: "{{ out }}"
        mode: "0600"
PLAY
run_play() {
  STUB_STATE=$work/state.json STUB_CLIENT=$client \
  ANSIBLE_ROLES_PATH="$root/hosts/ansible/roles" ansible-playbook -i localhost, -c local "$work/play.yml" \
    -e "k8s_backup_az=$work/az" -e "out=$work/env.lines" -e "k8s_backup_bin_dir=$root/hosts/ansible/roles/k8s_backup/files" \
    -e "k8s_backup_azure_account=exampleaccount" -e "k8s_backup_azure_client_id=$client" \
    -e "k8s_backup_azure_tenant_id=$tenant" -e "k8s_backup_azure_app_object_id=$object" \
    -e "k8s_backup_azure_cert_file=$pem" \
    -e "ansible_python_interpreter=$(command -v python3)"
}
# The play's check and wait steps reach the stub through the same environment as above.
run_play > "$work/play.log" 2>&1 || { cat "$work/play.log"; fail "azure_identity.yml, first run"; }
python3 "$script" check >/dev/null 2>&1 || fail "check after the play"
[ "$(grep -c '^ad app credential reset' "$work/state.json.az.log")" = 1 ] || fail "az upload count"
[ "$(state 'len(s["expired"])')" = 0 ] || fail "the expired certificate was not removed"
[ "$(cat "$pem.keyid")" = "$(state 'list(s["keys"])[0]')" ] || fail "key ID not recorded"
run_play > "$work/play.log" 2>&1 || { cat "$work/play.log"; fail "azure_identity.yml, second run"; }
[ "$(grep -c '^ad app credential reset' "$work/state.json.az.log")" = 1 ] || fail "a second run uploaded again"
for line in "AZURE_ACCOUNT_NAME=exampleaccount" "AZURE_CLIENT_ID=$client" "AZURE_TENANT_ID=$tenant" \
  "AZURE_APP_OBJECT_ID=$object" "AZURE_CLIENT_CERTIFICATE_PATH=$pem"; do
  grep -qx "$line" "$work/env.lines" || { cat "$work/env.lines"; fail "env line $line"; }
done
grep -q SAS "$work/env.lines" && fail "env lines still name a SAS"
echo "ok   7. azure_identity.yml uploads once, records the key ID, removes an expired certificate, writes the env lines"
echo "backup azure cert: 7 checks passed"
