#!/bin/bash
# /usr/local/libexec/agent-box/opnsense-offbox.sh: copy the box's OPNsense configuration backups off the box, into
# their own container in the Azure backup account (pick 222, docs/runbooks/copy-opnsense-backup-off-box.md). Runs as
# user `keys` from its daily timer; no session runs it, so it has no sudo line.
#   1. The box's own Azure certificate is rolled when 30 or fewer days are left (azure-cert.py renew, Graph addKey).
#      The key is made on the box and never leaves it; no Azure secret is stored anywhere.
#   2. The repository password is made on the box on the first run, and its one off-box copy is checked: the
#      newest version of the secret in Key Vault must be this password (opnsense-escrow.py ensure). Until it is,
#      nothing is copied, so no repository exists whose password lives only on the box.
#   3. restic backs up {work}/opnsense-backup into the repository (made on the first run), forgets snapshots past
#      the keep settings and prunes.
#   4. The newest configuration is read back from the newest snapshot and must be the same as the file on the box.
# A failed renewal still tries the copy with the current certificate, and the run fails at the end.
set -euo pipefail
umask 077

work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
settings=/etc/agent-keys/opnsense-offbox/settings.env   # written by the agent_box role; no secret in it
restic=$libexec/restic
cert=$libexec/azure-cert.py
escrow=$libexec/opnsense-escrow.py
src=$work/opnsense-backup
host=agent-box   # one fixed host name, so retention groups every snapshot even if the box is renamed
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

say() { echo "opnsense-offbox: $*"; }
die() { echo "opnsense-offbox: $*" >&2; exit 1; }

[[ -f $settings ]] || die "$settings is missing; set agent_box_opnsense_offbox in the inventory and run the agent_box role"
set -a
# shellcheck source=/dev/null
. "$settings"
set +a
# restic uses an account key or SAS before any other sign-in, so neither may come in from outside.
unset AZURE_ACCOUNT_KEY AZURE_ACCOUNT_SAS
for v in RESTIC_REPOSITORY RESTIC_PASSWORD_FILE AZURE_ACCOUNT_NAME AZURE_CLIENT_ID AZURE_TENANT_ID \
         AZURE_CLIENT_CERTIFICATE_PATH AZURE_APP_OBJECT_ID OFFBOX_VAULT_URL OFFBOX_VAULT_SECRET \
         OFFBOX_KEEP_DAILY OFFBOX_KEEP_MONTHLY; do
  [[ -n ${!v:-} ]] || die "$v is not set in $settings"
done
[[ $OFFBOX_KEEP_DAILY =~ ^[0-9]+$ && $OFFBOX_KEEP_MONTHLY =~ ^[0-9]+$ ]] || die "the keep settings must be whole numbers"

shopt -s nullglob
copies=("$src"/config-*.xml)
(( ${#copies[@]} > 0 )) || die "no config-*.xml in $src yet; opnsense-backup makes them"
newest=$(printf '%s\n' "${copies[@]}" | sort | tail -n 1)

status=0
if ! CENTRAL_HUB_BACKUP_ENV=$settings "$cert" renew; then
  echo "opnsense-offbox: the certificate renewal failed; trying the copy with the current certificate" >&2
  status=1
fi

# The password's one off-box copy comes first: with no copy in the vault, nothing is sent.
CENTRAL_HUB_BACKUP_ENV=$settings "$escrow" ensure || die "the vault does not hold the current repository password; nothing copied"
[[ -s $RESTIC_PASSWORD_FILE ]] || die "the repository password file is missing after the escrow step"

err=$(mktemp "$work/.offbox.XXXXXX")
back=$(mktemp "$work/.offbox.XXXXXX")
trap 'rm -f "$err" "$back"' EXIT

# Make the repository once. Exit 10 is restic's "repository does not exist"; anything else is a real failure.
rc=0
"$restic" --retry-lock 30m cat config >/dev/null 2>"$err" || rc=$?
case $rc in
  0) ;;
  10) "$restic" init >/dev/null; say "made the repository" ;;
  *) cat "$err" >&2; die "restic could not open the repository (exit $rc)" ;;
esac

"$restic" --retry-lock 30m backup --quiet --host "$host" --tag opnsense "$src"
"$restic" --retry-lock 30m forget --quiet --host "$host" --tag opnsense \
  --keep-daily "$OFFBOX_KEEP_DAILY" --keep-monthly "$OFFBOX_KEEP_MONTHLY" --prune

# A copy counts only once it reads back.
"$restic" --retry-lock 30m dump --host "$host" --tag opnsense latest "$newest" > "$back"
head -c 4096 "$back" | grep -q '<opnsense>' || die "the newest copy read back from the repository is not an OPNsense configuration"
cmp -s "$back" "$newest" || die "the newest copy read back from the repository differs from $newest"

say "copied ${#copies[@]} configurations off the box; $(basename "$newest") reads back the same"
exit "$status"
