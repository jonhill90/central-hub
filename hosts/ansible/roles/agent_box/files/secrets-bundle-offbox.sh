#!/bin/bash
# /usr/local/libexec/agent-box/secrets-bundle-offbox.sh: send the newest secrets bundle off the box (proposed
# D-0038 rule 10, pick 236, docs/runbooks/make-the-box-secrets-bundle.md). Runs as user `keys` from its daily
# timer, after the bundle's; no session runs it, so it has no sudo line.
# It reuses everything the OPNsense off-box copy has (pick 222): its settings, its Azure sign-in, its container,
# its restic repository and password, and its Key Vault, so it needs no Azure right of its own. With the switch on
# (dev-worker-address.sh box-backend-on) that repository is the OPNsense copy's folder on the Proxmox host's disk, over sftp (runbook
# back-up-c1-off-box.md, P5); the escrows stay in the vault.
#   1. The newest bundle must be encrypted to the box's own age recipient (and the Mac's, when one is set).
#   2. Both escrows must hold before anything is sent: the restic password, and the box's age identity as secret
#      BUNDLE_VAULT_SECRET. The box can write them and never read them back; the owner reads them at break-glass.
#   3. restic backs the bundle up under tag secrets-bundle, then forgets past the keep settings and prunes. Each
#      bundle has its own file name, so forget groups by host and tags, not by path: grouped by path, every
#      snapshot would be the only one in its group and none would ever be forgotten.
#   4. The bundle is read back from the repository: the same bytes, and it decrypts with the box's identity to a
#      tar holding prod/ or dev/. The clear tar is only ever piped to `tar -t`, never written to disk.
# No value is printed: one line with the bundle's name and size, or the step that failed.
set -euo pipefail
umask 077

work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
settings=/etc/agent-keys/opnsense-offbox/settings.env   # pick 222's settings; no secret in it
bundle_settings=/etc/agent-keys/secrets-bundle/settings.env
identity=/etc/agent-keys/secrets-bundle/age-identity.txt
bundles=/etc/agent-keys/secrets-bundle/bundles
restic=$libexec/restic
backend=/etc/agent-keys/box-backup/backend.env   # written by dev-worker-address.sh box-backend-on; absent: the settings' repository (Azure)
sops=$libexec/sops
age_keygen=$libexec/age-keygen
escrow=$libexec/opnsense-escrow.py
host=agent-box
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

say() { echo "secrets-bundle-offbox: $*"; }
die() { echo "secrets-bundle-offbox: $*" >&2; exit 1; }

for f in "$settings" "$bundle_settings"; do
  [[ -f $f ]] || die "$f is missing; set agent_box_opnsense_offbox and agent_box_secrets_bundle and run the agent_box role"
done
set -a
# shellcheck source=/dev/null
. "$settings"
# shellcheck source=/dev/null
. "$bundle_settings"
set +a
# restic uses an account key or SAS before any other sign-in, so neither may come in from outside.
# The Proxmox host's store instead of Azure, when the owner's switch is on (dev-worker-address.sh box-backend-on writes this file; box-backend-off removes it).
if [[ -f $backend ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$backend"
  set +a
fi
unset AZURE_ACCOUNT_KEY AZURE_ACCOUNT_SAS
for v in RESTIC_REPOSITORY RESTIC_PASSWORD_FILE BUNDLE_VAULT_SECRET BUNDLE_OFFBOX_KEEP_DAILY BUNDLE_OFFBOX_KEEP_MONTHLY; do
  [[ -n ${!v:-} ]] || die "$v is not set"
done
[[ $BUNDLE_OFFBOX_KEEP_DAILY =~ ^[1-9][0-9]*$ && $BUNDLE_OFFBOX_KEEP_MONTHLY =~ ^[0-9]+$ ]] || die "the keep settings must be whole numbers"

# The repository is Azure's (the default) or the Proxmox host's backup store, over sftp (the owner, 2026-11-18: back up on the Proxmox
# host, not Azure). With OFFBOX_RESTIC_SSH_CONFIG set, restic reaches the repository through that ssh config (its alias, the key and the
# pinned host key); the Azure sign-in below is still used for the vault, where the two small escrow secrets stay.
ropts=()
if [[ -n ${OFFBOX_RESTIC_SSH_CONFIG:-} ]]; then
  [[ $RESTIC_REPOSITORY == sftp:* ]] || die "OFFBOX_RESTIC_SSH_CONFIG is set but the repository is not an sftp one"
  [[ -r $OFFBOX_RESTIC_SSH_CONFIG ]] || die "$OFFBOX_RESTIC_SSH_CONFIG is missing; dev-worker-address.sh box-key writes it"
  ropts=(-o "sftp.args=-F $OFFBOX_RESTIC_SSH_CONFIG")
fi
rs() { "$restic" ${ropts[@]+"${ropts[@]}"} "$@"; }
[[ -s $identity ]] || die "$identity is missing; the agent_box role makes it"

# 1. The newest bundle, and who it is encrypted to.
newest=$(find "$bundles" -maxdepth 1 -name 'bundle-*.sops.json' -type f -printf '%f\n' 2>/dev/null | sort | tail -n 1)
[[ -n $newest ]] || die "no bundle in $bundles yet; secrets-bundle makes them"
bundle=$bundles/$newest
box_recipient=$("$age_keygen" -y "$identity")
recipients=$(python3 -I -c 'import json, sys; print(" ".join(a["recipient"] for a in json.load(open(sys.argv[1]))["sops"].get("age") or []))' "$bundle") \
  || die "$newest is not a SOPS file"
[[ " $recipients " == *" $box_recipient "* ]] || die "$newest is not encrypted to the box's own recipient; not sent"
if [[ -n ${BUNDLE_MAC_RECIPIENT:-} && " $recipients " != *" $BUNDLE_MAC_RECIPIENT "* ]]; then
  die "$newest is not encrypted to the Mac's recipient that the settings name; not sent"
fi

# 2. The escrows come first: with no off-box copy of the password and the identity, nothing is sent.
CENTRAL_HUB_BACKUP_ENV=$settings BACKUP_ESCROW_FILE=$identity BACKUP_ESCROW_SECRET=$BUNDLE_VAULT_SECRET "$escrow" ensure \
  || die "the vault does not hold the current repository password and age identity; nothing sent"
[[ -s $RESTIC_PASSWORD_FILE ]] || die "the repository password file is missing after the escrow step"

err=$(mktemp "$work/.bundle-offbox.XXXXXX")
back=$(mktemp "$work/.bundle-offbox.XXXXXX")
trap 'rm -f "$err" "$back"' EXIT
# The OPNsense copy prunes the same repository; wait for its lock rather than fail.
lock=(--retry-lock 30m)

# The repository is pick 222's. It must exist already (the OPNsense copy makes it); this job never makes one.
rc=0
rs "${lock[@]}" cat config >/dev/null 2>"$err" || rc=$?
[[ $rc == 0 ]] || { cat "$err" >&2; die "restic could not open the repository (exit $rc); the OPNsense off-box copy makes it"; }

# 3. Send, then keep KEEP_DAILY daily and KEEP_MONTHLY monthly; --prune deletes the rest from the account for good.
rs "${lock[@]}" backup --quiet --host "$host" --tag secrets-bundle "$bundle"
rs "${lock[@]}" forget --quiet --host "$host" --tag secrets-bundle --group-by host,tags \
  --keep-daily "$BUNDLE_OFFBOX_KEEP_DAILY" --keep-monthly "$BUNDLE_OFFBOX_KEEP_MONTHLY" --prune

# 4. A copy counts only once it reads back and opens.
rs "${lock[@]}" dump --host "$host" --tag secrets-bundle latest "$bundle" > "$back"
cmp -s "$back" "$bundle" || die "the bundle read back from the repository differs from $newest"
listing=$(SOPS_AGE_KEY_FILE=$identity "$sops" decrypt --input-type json --output-type binary "$back" | tar -tf -) \
  || die "the bundle read back from the repository does not decrypt with the box's identity to a tar"
grep -qE '^(prod|dev)/' <<<"$listing" || die "the bundle read back holds no prod/ or dev/ folder"

say "sent $newest ($(stat -c %s "$bundle") bytes) off the box; it reads back the same and opens with the box's identity"
