#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-offbox.sh: send the dev secrets store's newest Raft snapshot off the box
# (proposed D-0038 rule 8, pick 237, docs/runbooks/set-up-the-secrets-store.md). Runs as user `keys` from its hourly
# timer; no session runs it, so it has no sudo line.
# It reuses the OPNsense off-box copy's settings, Azure sign-in, container, restic password and Key Vault (pick 222),
# in a repository of its own, so it needs no Azure right of its own.
#   1. No store: the store runs inside the dev cluster (D-0058), so there is none unless the in-cluster store is on
#      (agent_box_openbao_in_cluster) and the dev rebuild's OpenTofu state holds dev VMs; then one "skipped: no store"
#      line, exit 0. With dev up and the rebuild hold (the rebuild wrapper writes it before a run that makes a fresh
#      store, restore-rebuilt or clear-hold removes it): "skipped: store rebuild in progress", exit 0, and a hold older
#      than 24 hours fails the run. A store that is there but whose sys/health is not 200 fails the run (rule 9: fail
#      loudly).
#   2. secrets-store snapshot copies a snapshot into the keys folder, through the admin AppRole, as it does by hand.
#   3. The restic password's escrow must hold before anything is sent, as for the OPNsense copy.
#   4. The repository is its own (SNAPSHOT_REPOSITORY). It is made only when restic says it does not exist (exit 10);
#      any other error, a lock or the network, fails the run and never makes one.
#   5. restic backs the snapshot up under tag openbao-dev, then forgets past the keep settings, grouped by host and
#      tags (each snapshot has its own file name). Only the first run on or after PRUNE_AFTER_HOUR UTC each day
#      prunes, which is what deletes data from the account.
#   6. The snapshot is read back: the same bytes. It opens only in a store with the seal key; restore-rebuilt
#      on a fresh dev store proves that (D-0058 rule 7).
# No value is printed: one line with the snapshot's name and size, or the step that failed.
set -euo pipefail
umask 077

work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
settings=/etc/agent-keys/opnsense-offbox/settings.env   # pick 222's settings; no secret in it
own=$work/secrets-store-offbox.env                       # this job's settings; no secret in it
store_settings=$work/secrets-store.json                  # the wrapper's settings: the store's address
inventory=/etc/agent-keys/rebuild-dev/inventory/hosts.yml   # the dev inventory: dev's Gateway address
state=$work/state/dev-vms.tfstate                        # the dev rebuild's OpenTofu state: the cluster the store is in
in_cluster=$work/openbao-in-cluster                      # "true" while the store inside the dev cluster is on
hold=$work/state/secrets-store.rebuilding               # the rebuild wrapper writes it; restore-rebuilt or clear-hold removes it
cacert=/etc/agent-keys/dev/secrets-store-ca.crt
snapshots=/etc/agent-keys/dev/openbao-snapshots
pruned=$work/state/secrets-store-offbox.pruned           # the UTC day of the last prune
wrapper=$libexec/secrets-store.sh
restic=$libexec/restic
escrow=$libexec/opnsense-escrow.py
now=$(date -u +%F-%H)
host=agent-box
tag=openbao-dev
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

say() { echo "secrets-store-offbox: $*"; }
die() { echo "secrets-store-offbox: $*" >&2; exit 1; }

for f in "$settings" "$own" "$store_settings"; do
  [[ -f $f ]] || die "$f is missing; set agent_box_opnsense_offbox and agent_box_secrets_store and run the agent_box role"
done

# 1. Is there a store? Only with the in-cluster store on and dev's VMs in the rebuild's state.
if [[ ! -f $in_cluster || $(tr -d '[:space:]' < "$in_cluster") != true ]]; then say "skipped: no store"; exit 0; fi
vms=$(python3 -I -c '
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except FileNotFoundError:
    print(0); sys.exit()
print(sum(len(r.get("instances", [])) for r in s.get("resources", [])
          if r.get("type") == "proxmox_virtual_environment_vm" and r.get("mode") == "managed"))' "$state") \
  || die "the dev rebuild's state at $state could not be read"
if [[ $vms == 0 ]]; then say "skipped: no store"; exit 0; fi
# A rebuild in progress (pick 238): dev is back but restore-rebuilt has not passed yet, so no snapshot of the
# empty store is taken, sent or kept. A hold older than a day is a rebuild left half done, which fails red.
if [[ -e $hold ]]; then
  (( $(date +%s) - $(stat -c %Y "$hold") < 86400 )) || die "the store's rebuild hold is over 24 hours old; finish restore-rebuilt, or run secrets-store clear-hold"
  say "skipped: store rebuild in progress"
  exit 0
fi
address=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["address"])' "$store_settings")
# Dev's names resolve to prod's Gateway, so the call goes to dev's Gateway by the dev inventory's address, as
# secrets-store.sh does (k8s_gitops_source_gateway_address, exactly one, IPv4).
gateway=$("$libexec/ansible-venv/bin/python3" -I -c '
import sys, yaml
found = set()
def walk(n):
    if isinstance(n, dict):
        for k, v in n.items():
            if k == "k8s_gitops_source_gateway_address" and isinstance(v, str) and v: found.add(v)
            else: walk(v)
    elif isinstance(n, list):
        for i in n: walk(i)
walk(yaml.safe_load(open(sys.argv[1])))
if len(found) != 1: sys.exit(1)
print(found.pop())' "$inventory" 2>/dev/null) && [[ $gateway =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
  die "the dev inventory $inventory gives no single IPv4 k8s_gitops_source_gateway_address; nothing sent"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 --resolve "$address:443:$gateway" --cacert "$cacert" "https://$address/v1/sys/health" || true)
[[ $code =~ ^[1-9] ]] || code=nothing   # curl prints 000 when nothing answered
[[ $code == 200 ]] || die "dev is up with the store on, but sys/health answered $code (200 is unsealed and active); nothing sent"

set -a
# shellcheck source=/dev/null
. "$settings"
# shellcheck source=/dev/null
. "$own"
set +a
# restic uses an account key or SAS before any other sign-in, so neither may come in from outside.
unset AZURE_ACCOUNT_KEY AZURE_ACCOUNT_SAS
for v in RESTIC_PASSWORD_FILE SNAPSHOT_REPOSITORY SNAPSHOT_KEEP_HOURLY SNAPSHOT_KEEP_DAILY SNAPSHOT_KEEP_MONTHLY SNAPSHOT_PRUNE_AFTER_HOUR; do
  [[ -n ${!v:-} ]] || die "$v is not set"
done
for v in SNAPSHOT_KEEP_HOURLY SNAPSHOT_KEEP_DAILY SNAPSHOT_KEEP_MONTHLY SNAPSHOT_PRUNE_AFTER_HOUR; do
  [[ ${!v} =~ ^[0-9]+$ ]] || die "$v must be a whole number"
done
(( SNAPSHOT_KEEP_HOURLY >= 1 && 10#$SNAPSHOT_PRUNE_AFTER_HOUR <= 23 )) || die "keep at least 1 hourly; the prune hour is 0-23"
# The repository is this job's own: never pick 222's, nor a path inside it, nor one that holds it. Both are
# compared the way restic reads them: for azure:<container>:<path>, restic cleans the path and drops its
# leading slash (internal/backend/azure/config.go, ParseConfig), so azure:c:p, azure:c:/p and azure:c://p/ are
# one repository, and azure:c: or azure:c:/ is the whole container.
repo_key() {
  python3 -I -c '
import posixpath, sys
s = sys.argv[1]
if s.startswith("azure:"):
    container, _, prefix = s[6:].partition(":")
    prefix = posixpath.normpath(prefix).lstrip("/")
    print("azure:" + container + ":/" + ("" if prefix == "." else prefix))
else:
    print(posixpath.normpath(s))' "$1"
}
own_repo=$(repo_key "$SNAPSHOT_REPOSITORY") other=''
[[ -z ${RESTIC_REPOSITORY:-} ]] || other=$(repo_key "$RESTIC_REPOSITORY")
if [[ -n $other && ( $own_repo == "$other" || $own_repo == "${other%/}"/* || $other == "${own_repo%/}"/* ) ]]; then
  die "SNAPSHOT_REPOSITORY must not be the OPNsense repository, nor inside it, nor hold it"
fi
export RESTIC_REPOSITORY=$SNAPSHOT_REPOSITORY

# 2. A snapshot, through the wrapper, which signs in with the admin AppRole and fails on an empty file.
"$wrapper" snapshot
newest=$(find "$snapshots" -maxdepth 1 -name 'raft-*.snap' -type f -printf '%f\n' 2>/dev/null | sort | tail -n 1)
[[ -n $newest && -s $snapshots/$newest ]] || die "no snapshot in $snapshots after secrets-store snapshot"
snap=$snapshots/$newest

# 3. The password's escrow comes first: with no off-box copy of it, nothing is sent.
CENTRAL_HUB_BACKUP_ENV=$settings "$escrow" ensure \
  || die "the vault does not hold the current repository password; nothing sent"
[[ -s $RESTIC_PASSWORD_FILE ]] || die "the repository password file is missing after the escrow step"

err=$(mktemp "$work/.store-offbox.XXXXXX")
back=$(mktemp "$work/.store-offbox.XXXXXX")
trap 'rm -f "$err" "$back"' EXIT
# The OPNsense copy and the bundle's send share the container; wait for a lock rather than fail.
lock=(--retry-lock 30m)

# 4. Its own repository, made only on restic's "does not exist" (exit 10).
rc=0
"$restic" "${lock[@]}" cat config >/dev/null 2>"$err" || rc=$?
case $rc in
  0) ;;
  10) "$restic" init >/dev/null; say "made the repository" ;;
  *) cat "$err" >&2; die "restic could not open the repository (exit $rc); not made, nothing sent" ;;
esac

# 5. Send, forget past the keep settings, and prune once a day.
# The snapshot and, when there is one, its cluster ID, which restore-rebuilt needs after a recovery.
files=("$snap")
[[ -s $snap.cluster ]] && files+=("$snap.cluster")
"$restic" "${lock[@]}" backup --quiet --host "$host" --tag "$tag" "${files[@]}"
prune=()
if [[ $(cat "$pruned" 2>/dev/null || true) != "${now%-*}" ]] && (( 10#${now##*-} >= 10#$SNAPSHOT_PRUNE_AFTER_HOUR )); then
  prune=(--prune)
fi
"$restic" "${lock[@]}" forget --quiet --host "$host" --tag "$tag" --group-by host,tags \
  --keep-hourly "$SNAPSHOT_KEEP_HOURLY" --keep-daily "$SNAPSHOT_KEEP_DAILY" --keep-monthly "$SNAPSHOT_KEEP_MONTHLY" "${prune[@]}"
if (( ${#prune[@]} )); then echo "${now%-*}" > "$pruned"; say "pruned the repository (once a day)"; fi

# 6. A copy counts only once it reads back the same.
"$restic" "${lock[@]}" dump --host "$host" --tag "$tag" latest "$snap" > "$back"
cmp -s "$back" "$snap" || die "the snapshot read back from the repository differs from $newest"

say "sent $newest ($(stat -c %s "$snap") bytes) off the box; it reads back the same"
