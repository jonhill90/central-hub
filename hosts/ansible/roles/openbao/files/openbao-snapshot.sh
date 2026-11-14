#!/bin/bash
# /usr/local/libexec/openbao-snapshot.sh PORT DIR KEEP: one Raft snapshot, then keep the newest KEEP.
# Logs in with the snapshot AppRole from 127.0.0.1 (role openbao); the token never leaves this
# process. Fails loudly: a failed login or save is a failed run, never an empty file (D-0038 rule 9).
set -euo pipefail
umask 077
port=$1 dir=$2 keep=$3
export BAO_ADDR=https://127.0.0.1:$port BAO_CACERT=/opt/openbao/tls/tls.crt
ids=/etc/openbao/snapshot
token=$(bao write -field=token auth/approle/login \
  role_id=@"$ids/role-id" secret_id=@"$ids/secret-id")
out=$dir/raft-$(date -u +%Y%m%dT%H%M%SZ).snap
BAO_TOKEN=$token bao operator raft snapshot save "$out.part"
[[ -s $out.part ]] || { echo "openbao-snapshot: empty snapshot" >&2; rm -f "$out.part"; exit 1; }
mv "$out.part" "$out"
BAO_TOKEN=$token bao token revoke -self >/dev/null
ls -1t "$dir"/raft-*.snap | tail -n +"$((keep + 1))" | xargs -r rm -f --
echo "openbao-snapshot: $out"
