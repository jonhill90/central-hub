#!/usr/bin/env bash
# The off-box send of the box's secrets bundle (hosts/ansible/roles/agent_box/files/secrets-bundle-offbox.sh, pick
# 236), against a local restic repository, the real SOPS and age, and a stand-in for the escrow script:
#   1. A normal send backs the newest bundle up under tag secrets-bundle, reads it back and opens it, after the
#      escrow was asked for the box's identity under the vault secret the settings name.
#   2. A failed escrow stops it before restic runs.
#   3. A bundle not encrypted to the box's own recipient is refused.
#   4. A Mac recipient in the settings that the bundle lacks is refused; with it in the bundle, it sends.
#   5. A corrupted read-back fails the run.
#   6. With no repository it fails, and makes none (the OPNsense copy makes it).
#   7. No password, identity or file content shows in the output, and the clear tar is never written to a file.
#   8. Retention works although every bundle has its own file name: with older snapshots on five past days and
#      keep-daily 2, keep-monthly 0, one send leaves two. Grouped by path, as restic does by default, none would go.
# restic, SOPS and age come from their GitHub releases, checked against the SHA-256s the role installs.
# Usage: .github/hosts-check/tests/test_secrets_bundle_offbox.sh   (needs curl, python3 with PyYAML, bunzip2)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
role=$root/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
def() { python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))[sys.argv[2]])' "$role/defaults/main.yml" "$1"; }

mkdir -p "$t/bin"
rv=$(def agent_box_restic_version)
curl -sSLf --retry 5 --retry-delay 10 -o "$t/restic.bz2" "https://github.com/restic/restic/releases/download/v$rv/restic_${rv}_linux_amd64.bz2"
echo "$(def agent_box_restic_sha256)  $t/restic.bz2" | sha256sum -c --quiet
bunzip2 -c "$t/restic.bz2" > "$t/bin/restic-real"
sv=$(def agent_box_sops_version)
curl -sSLf --retry 5 --retry-delay 10 -o "$t/bin/sops" "https://github.com/getsops/sops/releases/download/v$sv/sops-v$sv.linux.amd64"
echo "$(def agent_box_sops_sha256)  $t/bin/sops" | sha256sum -c --quiet
av=$(def agent_box_age_version)
curl -sSLf --retry 5 --retry-delay 10 -o "$t/age.tgz" "https://github.com/FiloSottile/age/releases/download/v$av/age-v$av-linux-amd64.tar.gz"
echo "$(def agent_box_age_sha256)  $t/age.tgz" | sha256sum -c --quiet
tar -xzf "$t/age.tgz" -C "$t" age/age-keygen && mv "$t/age/age-keygen" "$t/bin/age-keygen"
# restic, with a switch that corrupts what `dump` gives back.
cat > "$t/bin/restic" <<EOF
#!/bin/bash
if [[ " \$* " == *" dump "* && -e $t/corrupt ]]; then "$t/bin/restic-real" "\$@"; printf x; else exec "$t/bin/restic-real" "\$@"; fi
EOF
chmod +x "$t/bin/"*

mkdir -p "$t/work" "$t/keys/opnsense-offbox" "$t/keys/secrets-bundle/bundles" "$t/src/prod" "$t/src/dev"
echo "fake-prod-file-content" > "$t/src/prod/home.tfvars"
echo "fake-dev-file-content" > "$t/src/dev/identity.env"
"$t/bin/age-keygen" -o "$t/keys/secrets-bundle/age-identity.txt" 2>/dev/null
"$t/bin/age-keygen" -o "$t/other-identity.txt" 2>/dev/null
"$t/bin/age-keygen" -o "$t/mac-identity.txt" 2>/dev/null
box=$("$t/bin/age-keygen" -y "$t/keys/secrets-bundle/age-identity.txt")
other=$("$t/bin/age-keygen" -y "$t/other-identity.txt")
mac=$("$t/bin/age-keygen" -y "$t/mac-identity.txt")
head -c 32 /dev/urandom | base64 > "$t/keys/opnsense-offbox/restic.txt"

# Stand-in for opnsense-escrow.py: records what it was asked, and exits with what $t/escrow-rc holds.
echo 0 > "$t/escrow-rc"
cat > "$t/escrow" <<EOF
#!/bin/bash
[ "\$1" = ensure ] || exit 9
echo "\$CENTRAL_HUB_BACKUP_ENV|\$BACKUP_ESCROW_FILE|\$BACKUP_ESCROW_SECRET" > $t/escrow-args
exit "\$(cat $t/escrow-rc)"
EOF
chmod +x "$t/escrow"
cat > "$t/keys/opnsense-offbox/settings.env" <<EOF
RESTIC_REPOSITORY=$t/repo
RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt
EOF
write_bundle_settings() { # mac recipient, keep daily, keep monthly
  cat > "$t/keys/secrets-bundle/settings.env" <<EOF
BUNDLE_MAC_RECIPIENT=${1:-}
BUNDLE_KEEP=14
BUNDLE_VAULT_SECRET=secrets-bundle-age-identity
BUNDLE_OFFBOX_KEEP_DAILY=${2:-14}
BUNDLE_OFFBOX_KEEP_MONTHLY=${3:-6}
EOF
}
write_bundle_settings
make_bundle() { # name, recipients
  tar --sort=name -C "$t/src" -cf "$t/bundle.tar" prod dev
  "$t/bin/sops" encrypt --input-type binary --output-type json --age "$2" \
    --output "$t/keys/secrets-bundle/bundles/$1" "$t/bundle.tar"
}
sed -e "s|^work=.*|work=$t/work|" -e "s|^settings=.*|settings=$t/keys/opnsense-offbox/settings.env|" \
    -e "s|^bundle_settings=.*|bundle_settings=$t/keys/secrets-bundle/settings.env|" \
    -e "s|^identity=.*|identity=$t/keys/secrets-bundle/age-identity.txt|" \
    -e "s|^bundles=.*|bundles=$t/keys/secrets-bundle/bundles|" -e "s|^restic=.*|restic=$t/bin/restic|" \
    -e "s|^sops=.*|sops=$t/bin/sops|" -e "s|^age_keygen=.*|age_keygen=$t/bin/age-keygen|" -e "s|^escrow=.*|escrow=$t/escrow|" \
    "$role/files/secrets-bundle-offbox.sh" > "$t/send.sh"
grep -q "^escrow=$t/escrow" "$t/send.sh" && grep -q "^bundles=$t/" "$t/send.sh" || { echo "FAIL: the test could not point the script at its folders"; exit 1; }

fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
send() { bash "$t/send.sh" > "$t/out" 2>&1 && rc=0 || rc=$?; out=$(cat "$t/out"); all+=$out; }
snapshots() { RESTIC_REPOSITORY=$t/repo RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt "$t/bin/restic" snapshots --json --host agent-box --tag secrets-bundle 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin) or []))'; }
all=""

# 6 first: no repository yet.
make_bundle bundle-20261114T153000Z.sops.json "$box"
send
[[ $rc -ne 0 && $out == *"could not open the repository"* && ! -e $t/repo/config ]] && ok "6. no repository fails, and none is made" || bad "6. rc=$rc $out"
RESTIC_REPOSITORY=$t/repo RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt "$t/bin/restic" init --quiet >/dev/null

# 1
make_bundle bundle-20261115T153000Z.sops.json "$box"
send
if [[ $rc -eq 0 && $out == *"sent bundle-20261115T153000Z.sops.json"* && $(snapshots) == 1 ]] &&
   [[ $(cat "$t/escrow-args") == "$t/keys/opnsense-offbox/settings.env|$t/keys/secrets-bundle/age-identity.txt|secrets-bundle-age-identity" ]]; then
  ok "1. the newest bundle is sent under tag secrets-bundle, after the identity's escrow, and reads back and opens"
else bad "1. rc=$rc $out"; fi

# 2
echo 1 > "$t/escrow-rc"
send
[[ $rc -ne 0 && $out == *"nothing sent"* && $(snapshots) == 1 ]] && ok "2. a failed escrow stops it before restic" || bad "2. rc=$rc $out"
echo 0 > "$t/escrow-rc"

# 3
make_bundle bundle-20261116T153000Z.sops.json "$other"
send
[[ $rc -ne 0 && $out == *"not encrypted to the box's own recipient"* && $(snapshots) == 1 ]] && ok "3. a bundle not encrypted to the box is refused" || bad "3. rc=$rc $out"

# 4
make_bundle bundle-20261117T153000Z.sops.json "$box"
write_bundle_settings "$mac"
send
[[ $rc -ne 0 && $out == *"Mac's recipient"* ]] && ok "4a. a Mac recipient the bundle lacks is refused" || bad "4a. rc=$rc $out"
make_bundle bundle-20261118T153000Z.sops.json "$box,$mac"
send
# Same day as case 1. While fewer days than keep-daily hold snapshots, restic 0.19 also keeps the oldest one
# ("oldest daily snapshot"), so both stay.
[[ $rc -eq 0 && $out == *"sent bundle-20261118T153000Z.sops.json"* && $(snapshots) == 2 ]] \
  && ok "4b. with the Mac's recipient in the bundle, it sends" || bad "4b. rc=$rc $out"
write_bundle_settings

# 5
make_bundle bundle-20261119T153000Z.sops.json "$box"
touch "$t/corrupt"
send
[[ $rc -ne 0 && $out == *"differs from"* ]] && ok "5. a corrupted read-back fails the run" || bad "5. rc=$rc $out"
rm -f "$t/corrupt"

# 8
r() { RESTIC_REPOSITORY=$t/repo RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt "$t/bin/restic-real" "$@"; }
for d in 01 02 03 04 05; do
  make_bundle "bundle-202610${d}T153000Z.sops.json" "$box"
  r backup --quiet --host agent-box --tag secrets-bundle --time "2026-10-$d 15:30:00" \
    "$t/keys/secrets-bundle/bundles/bundle-202610${d}T153000Z.sops.json" >/dev/null
done
before=$(snapshots)
make_bundle bundle-20261120T153000Z.sops.json "$box"
write_bundle_settings "" 2 0
send
[[ $rc -eq 0 && $before -ge 6 && $(snapshots) == 2 ]] && ok "8. retention: $before snapshots on 6 days, keep-daily 2, leaves 2" \
  || bad "8. rc=$rc before=$before after=$(snapshots) $out"
write_bundle_settings

# 7
grep -qE 'decrypt[^|]*--output ' "$t/send.sh" && bad "7. the read-back writes the clear tar to a file"
secret=$(grep AGE-SECRET-KEY "$t/keys/secrets-bundle/age-identity.txt")
if [[ $all == *"$secret"* || $all == *"$(cat "$t/keys/opnsense-offbox/restic.txt")"* || $all == *fake-prod-file-content* ]]; then
  bad "7. a value shows in the output"
else ok "7. no password, identity or file content in the output"; fi
exit "$fail"
