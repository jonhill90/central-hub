#!/bin/bash
# /usr/local/libexec/agent-box/secrets-bundle.sh: one encrypted bundle of the box's private files (proposed D-0038
# rule 10, pick 228, docs/runbooks/make-the-box-secrets-bundle.md). Runs as user `keys` from its daily timer; no
# session runs it, so it has no sudo line.
#   1. tar the keys folder's environment folders (prod and dev, whichever exist), never this job's own folder.
#   2. SOPS encrypts the tar as a binary file to the box's own age identity, and to the owner's Mac when its
#      recipient is set (optional since pick 236), so either can decrypt it and nobody else can.
#   3. The bundle must decrypt again with the box's identity to the same bytes, or it is deleted and the run fails.
#   4. The newest KEEP bundles stay; older ones go.
# secrets-bundle-offbox.sh sends it off the box (pick 236); the box's identity is escrowed in the backup Key Vault,
# so the off-box copy opens without the box.
set -euo pipefail
umask 077

keys=/etc/agent-keys
libexec=/usr/local/libexec/agent-box
dir=$keys/secrets-bundle
settings=$dir/settings.env   # written by the agent_box role; no secret in it
identity=$dir/age-identity.txt
out=$dir/bundles
export HOME=/var/lib/agent-box PATH=/usr/local/bin:/usr/bin:/bin

say() { echo "secrets-bundle: $*"; }
die() { echo "secrets-bundle: $*" >&2; exit 1; }

[[ -f $settings ]] || die "$settings is missing; set agent_box_secrets_bundle in the inventory and run the agent_box role"
set -a
# shellcheck source=/dev/null
. "$settings"
set +a
# The Mac's recipient is optional (pick 236): the off-box copy opens with the box's identity, escrowed in the vault.
[[ -z ${BUNDLE_MAC_RECIPIENT:-} || $BUNDLE_MAC_RECIPIENT =~ ^age1[0-9a-z]{58}$ ]] || die "BUNDLE_MAC_RECIPIENT is not an age recipient"
[[ ${BUNDLE_KEEP:-} =~ ^[1-9][0-9]*$ ]] || die "BUNDLE_KEEP must be a whole number from 1"
[[ -s $identity ]] || die "$identity is missing; the agent_box role makes it"

box_recipient=$("$libexec/age-keygen" -y "$identity")
[[ $box_recipient =~ ^age1[0-9a-z]{58}$ ]] || die "the box's identity gives no age recipient"

srcs=()
for env in prod dev; do [[ -d $keys/$env ]] && srcs+=("$env"); done
(( ${#srcs[@]} > 0 )) || die "no prod or dev folder in $keys to bundle"

mkdir -p "$out"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
tarball=$(mktemp "$dir/.bundle.XXXXXX")
back=$(mktemp "$dir/.bundle.XXXXXX")
trap 'rm -f "$tarball" "$back"' EXIT

# Sorted names and fixed owner and times, so the same files always make the same tar.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' -C "$keys" -cf "$tarball" "${srcs[@]}"

bundle=$out/bundle-$stamp.sops.json
"$libexec/sops" encrypt --input-type binary --output-type json \
  --age "$box_recipient${BUNDLE_MAC_RECIPIENT:+,$BUNDLE_MAC_RECIPIENT}" --output "$bundle.part" "$tarball" \
  || { rm -f "$bundle.part"; die "sops could not encrypt the bundle"; }

# A bundle counts only once it reads back.
SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary \
  --output "$back" "$bundle.part" || { rm -f "$bundle.part"; die "the new bundle does not decrypt with the box's identity"; }
cmp -s "$back" "$tarball" || { rm -f "$bundle.part"; die "the new bundle decrypts to different bytes"; }
mv "$bundle.part" "$bundle"

find "$out" -maxdepth 1 -name 'bundle-*.sops.json' -printf '%f\n' | sort -r | tail -n +"$((BUNDLE_KEEP + 1))" |
  while read -r f; do rm -f -- "${out:?}/$f"; done

say "$(basename "$bundle"): ${srcs[*]}, $(stat -c %s "$tarball") bytes before encryption; reads back the same"
