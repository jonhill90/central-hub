#!/bin/bash
# /usr/local/libexec/agent-box/host-escrow.sh <name> <file>: keep one small secret file off the box, on the Proxmox host, when the
# host's backup store is the backend (dev-worker-address.sh box-backend-on). Run as the keys user by opnsense-offbox.sh and
# secrets-bundle-offbox.sh; no session runs it and it has no sudo line.
# It stands in for the Azure Key Vault escrow of the restic password and the box's age identity, which cannot be used while the Azure
# subscription is disabled. The file goes over sftp, with the box's own ssh config (the key that works only from the box, the host's key
# pinned), to escrow/<name> in the box's store folder on the host: inside the chroot of the boxbackup user, beside the restic
# repository but not part of it (restic lists only its own folders and files), 0600 in a 0700 folder, readable on the host by root only.
#   1. If escrow/<name> already holds exactly this file, nothing is written.
#   2. If it holds something else, or it cannot be read for any reason but "not found", this refuses: the held copy may be the only
#      one (the local file was lost and made again), and the host keeps no versions, so it is never overwritten. The owner decides.
#   3. Only when it is not there, the file is written to escrow/<name>.part, read back and compared, renamed to escrow/<name>, and read
#      back again. A torn or failed write never reaches the final name. Exit 0 only when the host holds it.
# The same trust domain as the backup disk: whoever has the host's disk has the password and the identity next to the data they open. The
# value is never printed: one line saying the name, or the step that failed.
set -euo pipefail
umask 077

cfg=/etc/agent-keys/box-backup/ssh_config
export PATH=/usr/local/bin:/usr/bin:/bin

die() { echo "host-escrow: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "usage: host-escrow.sh <name> <file>"
name=$1 file=$2
[[ $name =~ ^[a-z0-9-]{1,64}$ ]] || die "the name is lowercase letters, digits and hyphens"
[[ -s $file ]] || die "$file is missing or empty; nothing to keep"
[[ -r $cfg ]] || die "$cfg is missing; dev-worker-address.sh box-key writes it"

tdir=$(mktemp -d)
trap 'rm -rf -- "$tdir"' EXIT
# A batch of commands, each call bounded: a stalled connection fails in 30 s, not never. A leading "-" on a command ignores its failure.
sf() { timeout 30 sftp -F "$cfg" -o ConnectTimeout=10 -b - box-backup-target <<< "$1" > "$tdir/sftp.out" 2>&1; }

if sf "get escrow/$name $tdir/back"; then
  if cmp -s "$tdir/back" "$file"; then
    echo "host-escrow: ok: the host already holds the current $name"
    exit 0
  fi
  die "FAIL: the host holds a different $name than this file; not overwritten (it may be the only copy). Nothing was sent. The owner decides which one is right"
fi
# Only "not found" means there is no held copy. Any other failure (a refused or stalled connection, a permission error) says nothing about it.
grep -qi 'not found\|no such file' "$tdir/sftp.out" \
  || die "FAIL: could not tell whether the host holds $name: $(grep -viE 'sftp>|^$' "$tdir/sftp.out" | head -n 1 | cut -c1-160). Nothing was sent"
rm -f -- "$tdir/back"
sf "-mkdir escrow
put $file escrow/$name.part" || die "FAIL: could not write $name to the host's escrow folder: $(grep -viE 'sftp>|^$' "$tdir/sftp.out" | head -n 1 | cut -c1-160). Nothing was sent"
sf "get escrow/$name.part $tdir/back" && cmp -s "$tdir/back" "$file" || die "FAIL: $name read back from the host differs from the file (a torn write); it was not kept. Nothing was sent"
sf "rename escrow/$name.part escrow/$name" || die "FAIL: could not rename $name.part into place on the host. Nothing was sent"
rm -f -- "$tdir/back"
sf "get escrow/$name $tdir/back" && cmp -s "$tdir/back" "$file" || die "FAIL: $name read back from the host differs from the file; the host does not hold it. Nothing was sent"
echo "host-escrow: wrote the current $name to the host, and it reads back the same"
