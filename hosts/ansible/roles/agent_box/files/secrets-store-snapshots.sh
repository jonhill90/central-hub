#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-snapshots.sh: the secrets-store wrapper's two file steps on its
# snapshot folder, run only by the wrapper under its lock (picks 239, 240). It never reads a snapshot's contents.
#   take ADDR CACERT KEYS DIR KEEP ENV LOGIN
#                            sign in as AppRole LOGIN, snapshot-box or admin (its IDs in KEYS as
#                            openbao-LOGIN-role-id and -secret-id; agent pick 240: snapshot-box once the
#                            install tap turns it on, admin until then), write
#                            kv/ENV/snapshot-mark with this snapshot's own time (not a secret), save a Raft
#                            snapshot as DIR/raft-<time>.snap with the store's cluster ID beside it, revoke the
#                            token, then rotate DIR to KEEP. Fails loudly: never an empty file. The token goes to
#                            curl on stdin, never as an argument, and is never printed.
#   rotate DIR KEEP          keep the newest KEEP raft-*.snap directly in DIR, with their .cluster files; older
#                            ones go. Only DIR itself is read (-maxdepth 1), so no other folder is ever touched.
#   keep DIR KEPT CLUSTER    move every raft-*.snap in DIR whose .cluster file does not name CLUSTER (or that has
#                            none), with its .cluster file, into KEPT, which rotation never reads. A file already
#                            in KEPT is never overwritten: the run stops and moves nothing more. Removing anything
#                            from KEPT is a delete under D-0042 rule 6, for the owner's tap; nothing here does it.
set -euo pipefail
# On dev, secrets-store.sh sets SECRETS_STORE_RESOLVE (<store name>:443:<dev Gateway address>), because dev's names
# resolve to prod's Gateway; every curl here goes there. Unset (prod): curl as it is.
curl() { if [[ -n ${SECRETS_STORE_RESOLVE:-} ]]; then command curl --resolve "$SECRETS_STORE_RESOLVE" "$@"; else command curl "$@"; fi; }
umask 077

rotate() { # DIR KEEP
  find "$1" -maxdepth 1 -type f -name 'raft-*.snap' -printf '%f\n' | sort -r | tail -n +"$(($2 + 1))" |
    while read -r f; do rm -f -- "${1:?}/$f" "${1:?}/$f.cluster"; done
}

case ${1:-} in
  take)
    [[ $# -eq 8 && $6 =~ ^[1-9][0-9]*$ && $7 =~ ^(dev|prod)$ && $8 =~ ^(snapshot-box|admin)$ ]] ||
      { echo "usage: secrets-store-snapshots.sh take ADDR CACERT KEYS DIR KEEP ENV snapshot-box|admin" >&2; exit 2; }
    addr=$2/v1 cacert=$3 keys=$4 dir=$5 keep=$6 env=$7 login=$8
    mkdir -p "$dir"
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    out=$dir/raft-$stamp.snap
    # The store's cluster ID, which a rebuild changes (restore-rebuilt picks by it), from sys/health: no secret.
    cluster=$(curl -sS --cacert "$cacert" "$addr/sys/health" |
      python3 -I -c 'import json, sys; print(json.load(sys.stdin)["cluster_id"])') ||
      { echo "secrets-store: sys/health gave no cluster ID" >&2; exit 1; }
    token=$(python3 -I -c 'import json,sys; print(json.dumps({"role_id": open(sys.argv[1]).read().strip(), "secret_id": open(sys.argv[2]).read().strip()}))' \
      "$keys/openbao-$login-role-id" "$keys/openbao-$login-secret-id" |
      curl -sS --fail-with-body --cacert "$cacert" -X POST --data @- "$addr/auth/approle/login" |
      python3 -I -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])') && [[ -n $token ]] ||
      { echo "secrets-store: AppRole $login did not sign in" >&2; exit 1; }
    ok=1
    # A mark inside the snapshot: kv/<env>/snapshot-mark holds this snapshot's own time, which both restores
    # read back to prove the data came back. Not a secret.
    curl -sS --fail-with-body --cacert "$cacert" -H @- -X POST --data "{\"data\": {\"taken\": \"$stamp\"}}" \
      "$addr/kv/data/$env/snapshot-mark" -o /dev/null <<<"X-Vault-Token: $token" || ok=0
    [[ $ok == 1 ]] && { curl -sS --fail-with-body --cacert "$cacert" -H @- "$addr/sys/storage/raft/snapshot" \
      -o "$out.part" <<<"X-Vault-Token: $token" || ok=0; }
    curl -sS --cacert "$cacert" -H @- -X POST "$addr/auth/token/revoke-self" -o /dev/null <<<"X-Vault-Token: $token" || true
    [[ $ok == 1 && -s $out.part ]] || { rm -f "$out.part"; echo "secrets-store: snapshot failed or empty" >&2; exit 1; }
    mv "$out.part" "$out"
    echo "$cluster" > "$out.cluster"
    rotate "$dir" "$keep"
    echo "secrets-store: snapshot $(basename "$out"), $(stat -c %s "$out") bytes"
    ;;
  rotate)
    [[ $# -eq 3 && $3 =~ ^[1-9][0-9]*$ ]] || { echo "usage: secrets-store-snapshots.sh rotate DIR KEEP" >&2; exit 2; }
    rotate "$2" "$3"
    ;;
  keep)
    [[ $# -eq 4 && -n $4 ]] || { echo "usage: secrets-store-snapshots.sh keep DIR KEPT CLUSTER" >&2; exit 2; }
    dir=$2 kept=$3 cluster=$4
    mkdir -p "$kept" && chmod 0700 "$kept"
    moved=0
    while read -r f; do
      c=$(cat "$dir/$f.cluster" 2>/dev/null || true)
      [[ $c == "$cluster" ]] && continue
      for g in "$f" "$f.cluster"; do
        [[ -e $dir/$g ]] || continue
        [[ ! -e $kept/$g ]] || { echo "secrets-store: $kept/$g exists already; nothing overwritten, $moved moved" >&2; exit 1; }
        mv -n -- "$dir/$g" "$kept/$g"
        [[ -e $kept/$g && ! -e $dir/$g ]] || { echo "secrets-store: could not move $g into $kept; $moved moved" >&2; exit 1; }
      done
      moved=$((moved + 1))
    done < <(find "$dir" -maxdepth 1 -type f -name 'raft-*.snap' -printf '%f\n' | sort)
    echo "$moved"
    ;;
  *) echo "usage: secrets-store-snapshots.sh take ADDR CACERT KEYS DIR KEEP ENV LOGIN | rotate DIR KEEP | keep DIR KEPT CLUSTER" >&2; exit 2 ;;
esac
