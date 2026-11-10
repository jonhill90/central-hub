#!/usr/bin/env bash
# Prove prod's Keycloak database comes back from the backup (role k8s_backup, reader mode, RB1
# part D; runbook docs/runbooks/rebuild-k8s-layer-with-one-command.md, "Keycloak's database on
# dev"). Runs as root on a dev worker, from the rebuild's checks stage (tag restore_check), against
# a throwaway PostgreSQL pod in its own namespace. It follows the runbook "Back up c1 off the box",
# "Restore Keycloak's database", step 3, with crictl exec in place of kubectl exec.
#
#   c1-restore-identity.sh load <namespace>     bring the dump back from the snapshot the volume
#                                               restore used, count its rows, drop and load it into
#                                               the namespace's postgres container, count again
#   c1-restore-identity.sh recount <namespace>  count again (after Keycloak started on the data)
#   c1-restore-identity.sh clean                remove the counts (and any dump left); prove both are gone
#
# The dump holds prod's realm, its client secrets and its users' password hashes, so it stays in a
# mode-0700 folder for the minutes the check takes, and only counts are printed: realms, users,
# clients. Every restic call has --no-lock, and the node signs in as the read-only identity.
#
# Settings (besides those in c1-backup-lib.sh):
#   RESTORE_DUMP        the dump's path in the snapshot (default
#                       /var/lib/central-hub-backup/db-dumps/identity_sso-postgres-0.sql)
#   RESTORE_DUMP_STAGE  where it is brought back (default /var/tmp/c1-restore-identity)
#   BACKUP_CRICTL       crictl (default: crictl on the PATH)
set -euo pipefail
# The dump and the load's output are prod's secrets: no file here is readable by others.
umask 077
# shellcheck source=c1-backup-lib.sh
. "$(dirname "$0")/c1-backup-lib.sh"

cmd=${1:-}
case $cmd in load|recount) ns=${2:?usage: $0 $cmd <namespace>} ;; clean) ;; *) echo "usage: $0 load|recount <namespace> | clean" >&2; exit 2 ;; esac

backup_lib_init
record=$BACKUP_STATE/restored-volumes
counts=$BACKUP_STATE/identity-counts
dump_path=${RESTORE_DUMP:-/var/lib/central-hub-backup/db-dumps/identity_sso-postgres-0.sql}
stage=${RESTORE_DUMP_STAGE:-/var/tmp/c1-restore-identity}
crictl_bin=${BACKUP_CRICTL:-$(command -v crictl || true)}
r() { "$RESTIC" --no-lock "$@"; }

if [ "$cmd" = clean ]; then
  rm -rf "$stage" "$counts"
  [ ! -e "$stage" ] && [ ! -e "$counts" ] || die "could not remove $stage or $counts"
  echo "PASS: identity dump and counts removed from $BACKUP_HOST"
  exit 0
fi

[ -n "$crictl_bin" ] || die "no crictl on $BACKUP_HOST"
# The running postgres container of the namespace's pod, on this node.
cid=$("$crictl_bin" ps --name '^postgres$' --state running -o json | python3 -c '
import json, sys
ns = sys.argv[1]
ids = [c["id"] for c in json.load(sys.stdin).get("containers", [])
       if c.get("labels", {}).get("io.kubernetes.pod.namespace") == ns]
print(ids[0] if len(ids) == 1 else "")
' "$ns")
[ -n "$cid" ] || die "not exactly one running postgres container of namespace $ns on $BACKUP_HOST"

# Realms, users and clients in the loaded database, as "realms<TAB>users<TAB>clients".
# shellcheck disable=SC2016  # $POSTGRES_USER is the container's
db_counts() {
  "$crictl_bin" exec "$cid" sh -c 'psql -U "$POSTGRES_USER" -d keycloak -v ON_ERROR_STOP=1 -tA -F "	" -c "select (select count(*) from realm), (select count(*) from user_entity), (select count(*) from client)"'
}

if [ "$cmd" = recount ]; then
  [ -s "$counts" ] || die "no counts recorded on $BACKUP_HOST ($counts): run load first"
  want=$(cat "$counts")
  got=$(db_counts) || die "could not count the rows in namespace $ns"
  [ "$got" = "$want" ] || die "the database now holds realms, users, clients $(tr '\t' ' ' <<< "$got"), the dump held $(tr '\t' ' ' <<< "$want")"
  echo "PASS: after Keycloak started, the database still holds realms, users, clients $(tr '\t' ' ' <<< "$got"), as the dump"
  exit 0
fi

# load. The same snapshot the volume restore used, so dev's apps and its identity data are one
# point in time.
[ -s "$record" ] || die "no volume restore recorded on $BACKUP_HOST ($record)"
id=$(awk -F'\t' '$1 == "snapshot" {print $2}' "$record")
rm -rf "$stage"
mkdir -m 0700 "$stage"
# The dump and the load's output never outlive this run, pass or fail; only the counts stay.
trap 'rm -rf "$stage"' EXIT
dump=$stage/dump.sql
want_size=$(r ls --json "$id" "$dump_path" | python3 -c '
import json, sys
p = sys.argv[1]
for line in sys.stdin:
    n = json.loads(line) if line.strip() else {}
    if n.get("message_type", n.get("struct_type")) == "node" and n.get("path") == p and n.get("type") == "file":
        print(n.get("size", 0))
        break
' "$dump_path")
[ -n "$want_size" ] || die "snapshot $id has no dump at $dump_path"
r dump "$id" "$dump_path" > "$dump"
size=$(stat -c %s "$dump")
[ "$size" = "$want_size" ] || die "the dump came back with $size bytes, the snapshot lists $want_size"
tail -n 5 "$dump" | grep -q '^-- PostgreSQL database cluster dump complete' || die "the dump in snapshot $id is cut short"

# Rows of each table in the dump's COPY blocks, as "realms<TAB>users<TAB>clients".
want=$(python3 -c '
import re, sys
tables = {"realm": 0, "user_entity": 0, "client": 0}
cur = None
seen = set()
with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
    for line in f:
        if cur is None:
            m = re.match(r"COPY public\.(\w+) \(", line)
            if m and m.group(1) in tables:
                cur = m.group(1)
                seen.add(cur)
        elif line.rstrip("\n") == "\\.":
            cur = None
        else:
            tables[cur] += 1
missing = [t for t in tables if t not in seen]
if missing:
    sys.exit("the dump has no rows section for: " + ", ".join(missing))
print("%d\t%d\t%d" % (tables["realm"], tables["user_entity"], tables["client"]))
' "$dump") || die "the dump is not a Keycloak database: $want"
echo "dump: snapshot $id, $size bytes, complete; realms, users, clients $(tr '\t' ' ' <<< "$want")"

# The runbook's step 3: drop the keycloak database, then load the whole dump. Role errors are
# expected (pg_dumpall makes the roles, which exist); a FATAL is not. The load's output is never
# printed: it can quote rows.
# shellcheck disable=SC2016  # $POSTGRES_USER is the container's
"$crictl_bin" exec "$cid" sh -c 'dropdb -U "$POSTGRES_USER" --if-exists keycloak'
# shellcheck disable=SC2016
"$crictl_bin" exec -i "$cid" sh -c 'psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=0' < "$dump" > "$stage/load.log" 2>&1 || true
if grep -q FATAL "$stage/load.log"; then
  die "psql stopped with FATAL while loading the dump ($(grep -c FATAL "$stage/load.log") lines; its output is not kept, it can quote rows)"
fi
echo "load: $(grep -c ERROR "$stage/load.log" || true) ERROR lines (roles that exist are expected), no FATAL"
got=$(db_counts) || die "could not count the rows in namespace $ns after the load"
[ "$got" = "$want" ] || die "the loaded database holds realms, users, clients $(tr '\t' ' ' <<< "$got"), the dump $(tr '\t' ' ' <<< "$want")"
printf '%s\n' "$want" > "$counts"
chmod 0600 "$counts"
echo "PASS: prod's Keycloak database from snapshot $id loaded by the runbook's step 3: realms, users, clients $(tr '\t' ' ' <<< "$got"), as the dump"
