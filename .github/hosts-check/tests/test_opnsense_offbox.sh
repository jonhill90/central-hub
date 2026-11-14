#!/usr/bin/env bash
# The agent box's off-box copy of OPNsense's configuration (hosts/ansible/roles/agent_box/files/opnsense-offbox.sh,
# pick 222), against a local restic repository and a stand-in for the certificate script:
#   1. The first run makes the repository, backs up, and reads the newest copy back.
#   2. A second run adds a snapshot to the same repository.
#   3. A failed certificate renewal still copies, and fails the run.
#   4. A missing password file, a missing setting and an empty folder each stop it before restic runs.
#   5. A wrong password fails it (restic can't open the repository), without making a new one.
# restic comes from its GitHub release, checked against the SHA-256 the role installs (agent_box defaults).
# Usage: .github/hosts-check/tests/test_opnsense_offbox.sh   (needs curl, python3 with PyYAML, bunzip2)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
role=$root/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

ver=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["agent_box_restic_version"])' "$role/defaults/main.yml")
sum=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["agent_box_restic_sha256"])' "$role/defaults/main.yml")
curl -sSLf --retry 5 --retry-delay 10 -o "$t/restic.bz2" \
  "https://github.com/restic/restic/releases/download/v$ver/restic_${ver}_linux_amd64.bz2"
echo "$sum  $t/restic.bz2" | sha256sum -c --quiet
bunzip2 -c "$t/restic.bz2" > "$t/restic"
chmod +x "$t/restic"

mkdir -p "$t/work/opnsense-backup" "$t/keys"
printf '<?xml version="1.0"?>\n<opnsense>\n  <system><hostname>fw-one</hostname></system>\n</opnsense>\n' \
  > "$t/work/opnsense-backup/config-20261114T143000Z.xml"
printf '<?xml version="1.0"?>\n<opnsense>\n  <system><hostname>fw-two</hostname></system>\n</opnsense>\n' \
  > "$t/work/opnsense-backup/config-20261115T143000Z.xml"
head -c 32 /dev/urandom | base64 > "$t/keys/restic.txt"
# Stand-in for azure-cert.py: exits with what $t/cert-rc holds, and checks it was given the settings file.
echo 0 > "$t/cert-rc"
cat > "$t/cert" <<EOF
#!/bin/sh
[ "\$CENTRAL_HUB_BACKUP_ENV" = "$t/keys/settings.env" ] || { echo "cert: wrong settings file" >&2; exit 9; }
[ "\$1" = renew ] || exit 9
exit "\$(cat $t/cert-rc)"
EOF
chmod +x "$t/cert"
write_settings() {
  cat > "$t/keys/settings.env" <<EOF
RESTIC_REPOSITORY=$t/repo
RESTIC_PASSWORD_FILE=${1:-$t/keys/restic.txt}
AZURE_ACCOUNT_NAME=examplec1backup
AZURE_CLIENT_ID=33333333-3333-3333-3333-333333333333
AZURE_TENANT_ID=22222222-2222-2222-2222-222222222222
AZURE_CLIENT_CERTIFICATE_PATH=$t/keys/azure.pem
AZURE_APP_OBJECT_ID=44444444-4444-4444-4444-444444444444
OFFBOX_KEEP_DAILY=30
OFFBOX_KEEP_MONTHLY=12
EOF
}
write_settings
sed -e "s|^work=.*|work=$t/work|" -e "s|^settings=.*|settings=$t/keys/settings.env|" \
    -e "s|^restic=.*|restic=$t/restic|" -e "s|^cert=.*|cert=$t/cert|" \
    "$role/files/opnsense-offbox.sh" > "$t/offbox.sh"
grep -q "^work=$t/work" "$t/offbox.sh" && grep -q "^restic=$t/restic" "$t/offbox.sh" || { echo "FAIL: the test could not point the script at its folders"; exit 1; }

fail=0
snapshots() { RESTIC_REPOSITORY=$t/repo RESTIC_PASSWORD_FILE=$t/keys/restic.txt "$t/restic" snapshots --json --host agent-box --tag opnsense | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

# 1
if out=$(bash "$t/offbox.sh" 2>&1) && [[ $out == *"made the repository"* && $out == *"config-20261115T143000Z.xml reads back the same"* ]]; then
  ok "first run makes the repository and reads the newest copy back"
else bad "first run: $out"; fi
[[ $(snapshots) == 1 ]] && ok "one snapshot after the first run" || bad "snapshots after the first run: $(snapshots)"

# 2
if out=$(bash "$t/offbox.sh" 2>&1) && [[ $out != *"made the repository"* ]]; then ok "second run uses the same repository"; else bad "second run: $out"; fi

# 3
echo 1 > "$t/cert-rc"
if out=$(bash "$t/offbox.sh" 2>&1); then bad "a failed renewal must fail the run: $out"
elif [[ $out == *"renewal failed"* && $out == *"reads back the same"* ]]; then ok "a failed renewal still copies, and fails the run"
else bad "failed renewal: $out"; fi
echo 0 > "$t/cert-rc"
[[ $(snapshots) -ge 2 ]] && ok "snapshots kept by the keep settings" || bad "snapshots: $(snapshots)"

# 4
refuse() { local why=$1; shift; if out=$(bash "$t/offbox.sh" 2>&1); then bad "$why: should stop"; elif [[ $out == *"$*"* ]]; then ok "$why"; else bad "$why: $out"; fi; }
write_settings "$t/keys/missing.txt"
refuse "stops with no password file" "password file is missing"
write_settings
sed -i '/^AZURE_APP_OBJECT_ID=/d' "$t/keys/settings.env"
refuse "stops with a setting missing" "AZURE_APP_OBJECT_ID is not set"
write_settings
mv "$t/work/opnsense-backup" "$t/work/held"; mkdir "$t/work/opnsense-backup"
refuse "stops with no copies to send" "no config-*.xml"
rmdir "$t/work/opnsense-backup"; mv "$t/work/held" "$t/work/opnsense-backup"

# 5
echo wrong > "$t/keys/wrong.txt"
write_settings "$t/keys/wrong.txt"
refuse "a wrong password fails, and makes no new repository" "could not open the repository"
write_settings

exit "$fail"
