#!/usr/bin/env bash
# Test of the restore's choice among folders of one claim (c1-restore-volumes.sh and c1-restore-pv-map.sh, role k8s_backup),
# on one machine, with the real restic and etcd the role installs (versions and sums from its defaults/main.yml).
#
# Prod's snapshot b314a21a held three folders for openbao/data-openbao-0 (the claim made again after each rebuild, the old
# folders kept by reclaim policy Retain) and the restore refused. It now restores the folder of the volume the claim's own
# object in the etcd backup taken with the snapshot names, and refuses when it can't read that. Cases:
#   1. one folder for a claim, two folders, three folders (the bound one neither the newest nor the first by name): the
#      bound folder comes back whole, the others never move into place, a claim with one folder is untouched, and `inspect`
#      shows every folder with its newest file time and which one is bound
#   2. refuses, writing nothing: no etcd record for the claim, a record that names a volume with no folder, a claim whose
#      object names two volumes, and no etcd snapshot within the window
#   3. a pinned snapshot ID is the one restored while a newer snapshot of the same host exists (the rebuilt, empty nodes
#      of a rerun), and an ID that is not a volume snapshot of the host is refused
# Usage: .github/hosts-check/tests/test_restore_pv.sh   (needs curl, python3 with PyYAML, bunzip2, tar)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
role=$root/hosts/ansible/roles/k8s_backup
work=$(mktemp -d)
cleanup() {
  [ -n "${etcd_pid:-}" ] && kill "$etcd_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

CLUSTER_ETCD_VERSION=3.7.0
CLUSTER_ETCD_SHA256=b05cb07f5686dab8f9cdab89986b44f0dd24aaf5c627176aff325e21fa56f9f0
read -r restic_v restic_sum etcd_v etcd_sum < <(python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(d["k8s_backup_restic_version"], d["k8s_backup_restic_sha256"], d["k8s_backup_etcd_version"], d["k8s_backup_etcd_sha256"])
' "$role/defaults/main.yml")
fetch() { curl -fsSL --retry 5 --retry-all-errors --retry-delay 15 -o "$3" "$1"; echo "$2  $3" | sha256sum --check --quiet; }
bin=$work/bin
mkdir -p "$bin" "$work/cluster"
fetch "https://github.com/restic/restic/releases/download/v$restic_v/restic_${restic_v}_linux_amd64.bz2" "$restic_sum" "$work/restic.bz2"
bunzip2 -c "$work/restic.bz2" > "$bin/restic"
fetch "https://github.com/etcd-io/etcd/releases/download/v$etcd_v/etcd-v$etcd_v-linux-amd64.tar.gz" "$etcd_sum" "$work/etcd.tgz"
tar -xzf "$work/etcd.tgz" -C "$bin" --strip-components=1 "etcd-v$etcd_v-linux-amd64/etcd" "etcd-v$etcd_v-linux-amd64/etcdctl" "etcd-v$etcd_v-linux-amd64/etcdutl"
fetch "https://github.com/etcd-io/etcd/releases/download/v$CLUSTER_ETCD_VERSION/etcd-v$CLUSTER_ETCD_VERSION-linux-amd64.tar.gz" "$CLUSTER_ETCD_SHA256" "$work/cluster-etcd.tgz"
tar -xzf "$work/cluster-etcd.tgz" -C "$work/cluster" --strip-components=1 "etcd-v$CLUSTER_ETCD_VERSION-linux-amd64/etcd"
cp "$role"/files/*.sh "$bin/"
chmod 0755 "$bin"/*

export BACKUP_BIN=$bin TMPDIR=$work CENTRAL_HUB_BACKUP_ENV=$work/none.env
export RESTIC_REPOSITORY=$work/repo RESTIC_PASSWORD=ci-only-not-a-secret RESTIC_CACHE_DIR=$work/cache
pass=0
ok() { echo "ok - $*"; pass=$((pass + 1)); }
fail() { echo "not ok - $*" >&2; exit 1; }

# The cluster's etcd: the objects a real cluster holds for the claims. A PersistentVolumeClaim's value here is plain text
# naming its volume; a real one is protobuf, in which the same name is the same bytes (spec.volumeName).
ep=http://127.0.0.1:12399
"$work/cluster/etcd" --name ci --data-dir "$work/etcd-data" \
  --listen-client-urls "$ep" --advertise-client-urls "$ep" \
  --listen-peer-urls http://127.0.0.1:12398 --initial-advertise-peer-urls http://127.0.0.1:12398 \
  --initial-cluster ci=http://127.0.0.1:12398 > "$work/etcd.log" 2>&1 &
etcd_pid=$!
for _ in $(seq 60); do "$bin/etcdctl" --endpoints "$ep" endpoint health >/dev/null 2>&1 && break; sleep 1; done
e() { "$bin/etcdctl" --endpoints "$ep" "$@"; }
e put /registry/namespaces/kube-system '{"kind":"Namespace"}' >/dev/null
mkdir -p "$work/kube/pki/etcd" "$work/kube/manifests"
echo fake > "$work/kube/pki/ca.crt"; echo fake > "$work/kube/manifests/etcd.yaml"
# One etcd snapshot at a time, so "nearest in time" is the one just taken.
etcd_backup() {
  old=$("$bin/restic" snapshots --json --tag etcd 2>/dev/null | python3 -c 'import json,sys; print(*[s["id"] for s in (json.load(sys.stdin) or [])])' 2>/dev/null || true)
  BACKUP_HOST=ci-cp BACKUP_STATE=$work/cp-state ETCDCTL_ENDPOINTS=$ep ETCD_CACERT='' KUBE_DIR=$work/kube "$bin/c1-backup-etcd.sh" > "$work/etcd-backup.log" 2>&1 || { cat "$work/etcd-backup.log"; fail "the etcd backup failed"; }
  # shellcheck disable=SC2086
  [ -z "${old:-}" ] || "$bin/restic" forget $old >/dev/null
}

# Three generations of one claim's volume, and a claim with one folder.
A=pvc-0b92a555-3693-44c3-b2ec-cc1f4a4143c9   # the oldest, first by name
B=pvc-9027e805-67d4-4f3d-aec1-8198593c58fb   # the one the claim is bound to: neither the newest nor the first
C=pvc-e6e3d6a4-0596-457b-b379-61dea0cc67de   # the newest files
O=pvc-11111111-2222-3333-4444-555555555555
data=$work/prod/local-path
mkfolder() { # <folder> <content> <time>
  mkdir -p "$data/$1/raft"; echo "$2" > "$data/$1/raft/raft.db"; echo "$2" > "$data/$1/vault.db"
  TZ=UTC touch -d "$3" "$data/$1/raft/raft.db" "$data/$1/vault.db"
}
seed() { # <with the newest generation: yes|no>
  rm -rf "$data" && mkdir -p "$data"
  mkfolder "${A}_openbao_data-openbao-0" generation-a "2026-01-01 00:00:00"
  mkfolder "${B}_openbao_data-openbao-0" generation-b "2026-11-21 08:29:00"
  [ "$1" = no ] || mkfolder "${C}_openbao_data-openbao-0" generation-c "2026-11-21 08:35:00"
  mkfolder "${O}_media_jellyfin-config" only-one "2026-05-05 05:05:05"
}
seed yes
e put /registry/persistentvolumeclaims/openbao/data-openbao-0 "k8s-ish bytes volumeName=$B bound" >/dev/null
e put /registry/persistentvolumeclaims/media/jellyfin-config "k8s-ish bytes volumeName=$O bound" >/dev/null
etcd_backup
BACKUP_HOST=ci-prod BACKUP_STATE=$work/prod-state BACKUP_VOLUME_PATHS=$data "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || { cat "$work/vol.log"; fail "the volume backup failed"; }
snap3=$("$bin/restic" snapshots --json --host ci-prod --tag volumes | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1]["id"])')

# A restore lands where the snapshot's folders were (prod's path), on a data disk that starts empty.
dev=$data
env_dev() { env BACKUP_HOST=ci-dev "BACKUP_STATE=$work/dev-state-$1" RESTORE_SOURCE_HOST=ci-prod "RESTORE_PATH=$dev" RESTORE_REQUIRE_MOUNT= "${@:2}"; }
fresh() { rm -rf "$dev" "$work/prod/.c1-restore-stage" && mkdir -p "$dev"; }

echo "== 1. one, two and three folders for a claim"
fresh
out=$(env_dev 1 "$bin/c1-restore-volumes.sh" restore 2>&1) || { echo "$out"; fail "the restore with three folders for one claim failed"; }
echo "$out"
grep -q "^mapped ${B}_openbao_data-openbao-0 -> openbao/data-openbao-0" <<< "$out" || fail "the bound folder was not mapped"
grep -q "^mapped ${O}_media_jellyfin-config -> media/jellyfin-config" <<< "$out" || fail "the claim with one folder was not mapped"
grep -q "^not restored: ${A}_openbao_data-openbao-0" <<< "$out" || fail "the oldest folder was not named as left out"
grep -q "^not restored: ${C}_openbao_data-openbao-0" <<< "$out" || fail "the newest folder was not named as left out"
[ "$(cat "$dev/openbao/data-openbao-0/vault.db")" = generation-b ] || fail "the restored folder is not the bound one"
[ "$(cat "$dev/openbao/data-openbao-0/raft/raft.db")" = generation-b ] || fail "the restored folder is not whole"
[ "$(cat "$dev/media/jellyfin-config/vault.db")" = only-one ] || fail "the claim with one folder did not come back"
[ ! -e "$work/prod/.c1-restore-stage" ] && [ -z "$(find "$dev" -name '*generation-[ac]*')" ] || fail "a folder that is not bound was moved into place"
grep -qP "^snapshot\t$snap3\tci-prod" <<< "$out" || fail "the record does not name the snapshot"
[ -s "$work/dev-state-1/forget-hold" ] || fail "the restore did not set the forget hold"
ok "three folders for one claim: the one the etcd backup binds (neither newest nor first) comes back whole, the other two never move, a claim with one folder is as before"

out=$(env_dev 1 "$bin/c1-restore-volumes.sh" check 2>&1) || { echo "$out"; fail "check failed after the restore"; }
out=$(env_dev 1 "$bin/c1-restore-volumes.sh" owner openbao/data-openbao-0 "$(id -u)" 2>&1) || { echo "$out"; fail "owner could not map the snapshot after the restore"; }
grep -q '^PASS: ' <<< "$out" || fail "owner did not pass"
ok "check and owner map the same folders after the restore (the record is kept in the node's state)"

out=$(env_dev 9 "$bin/c1-restore-volumes.sh" inspect 2>&1) || { echo "$out"; fail "inspect failed"; }
echo "$out"
grep -qP "^${A}_openbao_data-openbao-0\topenbao/data-openbao-0\t2\t\d+\t2026-01-01T00:00:00\tnot bound: left out" <<< "$out" || fail "inspect did not list the oldest folder with its time"
grep -qP "^${B}_openbao_data-openbao-0\topenbao/data-openbao-0\t2\t\d+\t2026-11-21T08:29:00\tBOUND: restored" <<< "$out" || fail "inspect did not mark the bound folder"
grep -qP "^${C}_openbao_data-openbao-0\topenbao/data-openbao-0\t2\t\d+\t2026-11-21T08:35:00\tnot bound: left out" <<< "$out" || fail "inspect did not list the newest folder"
grep -qP "^${O}_media_jellyfin-config\tmedia/jellyfin-config\t2\t\d+\t2026-05-05T05:05:05\tonly folder for the claim" <<< "$out" || fail "inspect did not list the single folder"
grep -qP '^pv-record\tetcd\t' <<< "$out" || fail "inspect did not name the etcd backup it read"
[ ! -e "$work/dev-state-9/restored-volumes" ] || fail "inspect wrote a restore record"
ok "inspect lists every folder with files, bytes, newest file time and what the restore does with it, and writes nothing"

# Two folders: the bound one is the older.
seed no
BACKUP_HOST=ci-prod2 BACKUP_STATE=$work/prod-state2 BACKUP_VOLUME_PATHS=$data "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the second volume backup failed"
etcd_backup
fresh
env_dev 2 RESTORE_SOURCE_HOST=ci-prod2 "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1 || { cat "$work/r.log"; fail "the restore with two folders failed"; }
[ "$(cat "$dev/openbao/data-openbao-0/vault.db")" = generation-b ] || fail "two folders: not the bound one"
ok "two folders for one claim: the bound one comes back"

echo "== 2. what it refuses, writing nothing"
refuse() { # <label> <state> <expected text> [env...]
  fresh
  if env_dev "$2" "${@:4}" "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1; then cat "$work/r.log"; fail "the restore passed: $1"; fi
  grep -q "$3" "$work/r.log" || { cat "$work/r.log"; fail "it failed for another reason: $1"; }
  [ -z "$(ls -A "$dev")" ] || fail "the refused restore left files behind: $1"
  ok "refused ($1)"
}
# a snapshot of the claim with all three folders again, for each refusal
seed yes
BACKUP_HOST=ci-prod3 BACKUP_STATE=$work/prod-state3 BACKUP_VOLUME_PATHS=$data "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the third volume backup failed"
e del /registry/persistentvolumeclaims/openbao/data-openbao-0 >/dev/null
etcd_backup
refuse "no record of the claim in the etcd backup" 3 "DUPLICATE: more than one folder for the same claim: openbao/data-openbao-0 <- .*holds no bound volume" RESTORE_SOURCE_HOST=ci-prod3
e put /registry/persistentvolumeclaims/openbao/data-openbao-0 "bytes volumeName=pvc-99999999-9999-9999-9999-999999999999" >/dev/null
etcd_backup
refuse "the record names a volume that has no folder" 4 "which has no folder in the snapshot" RESTORE_SOURCE_HOST=ci-prod3
e put /registry/persistentvolumeclaims/openbao/data-openbao-0 "bytes volumeName=$A and volumeName=$B" >/dev/null
etcd_backup
refuse "the claim's object names two volumes" 5 "names more than one volume" RESTORE_SOURCE_HOST=ci-prod3
e put /registry/persistentvolumeclaims/openbao/data-openbao-0 "bytes volumeName=$B" >/dev/null
etcd_backup
refuse "no etcd snapshot within the window" 6 "no etcd snapshot within 0s" RESTORE_SOURCE_HOST=ci-prod3 RESTORE_ETCD_WINDOW=0
fresh
env_dev 8 RESTORE_SOURCE_HOST=ci-prod3 "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1 || { cat "$work/r.log"; fail "the restore with the record back failed"; }
[ "$(cat "$dev/openbao/data-openbao-0/vault.db")" = generation-b ] || fail "with the record back, not the bound folder"
ok "the same snapshot restores once the etcd record is back"

echo "== 3. a pinned snapshot"
# A later snapshot of the same host with nothing in it: what a backup of rebuilt, empty nodes makes.
rm -rf "$data" && mkdir -p "$data"
BACKUP_HOST=ci-prod BACKUP_STATE=$work/prod-state-empty BACKUP_VOLUME_PATHS=$data "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || { cat "$work/vol.log"; fail "the empty backup failed"; }
newest=$("$bin/restic" snapshots --json --host ci-prod --tag volumes | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin), key=lambda s: s["time"])[-1]["id"])')
[ "$newest" != "$snap3" ] || fail "the empty backup made no newer snapshot"
fresh
out=$(env_dev 10 RESTORE_SNAPSHOT="$snap3" "$bin/c1-restore-volumes.sh" restore 2>&1) || { echo "$out"; fail "the pinned restore failed"; }
grep -q "^RESTORED: snapshot $snap3" <<< "$out" || { echo "$out"; fail "the pinned restore did not take the pinned snapshot"; }
fresh
out=$(env_dev 11 "$bin/c1-restore-volumes.sh" restore 2>&1) || true
grep -q "snapshot $newest" <<< "$out" || { echo "$out"; fail "'latest' did not take the newer, empty snapshot (the case the pin guards)"; }
ok "a pinned ID restores the pinned snapshot while a newer, empty one of the same host exists; 'latest' would have taken the empty one"
fresh
if env_dev 12 RESTORE_SNAPSHOT=0000000000000000000000000000000000000000000000000000000000000000 "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1; then fail "an ID that is no snapshot was accepted"; fi
cpid=$("$bin/restic" snapshots --json --host ci-cp --tag etcd | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1]["id"])')
if env_dev 13 RESTORE_SNAPSHOT="$cpid" "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1; then fail "an etcd snapshot ID was accepted as the volume snapshot"; fi
[ -z "$(ls -A "$dev")" ] || fail "a refused pin left files behind"
ok "an ID that is no snapshot, or not a volume snapshot of the host, is refused and writes nothing"

echo "== 4. the plan before a teardown"
# The pre-teardown drill maps the snapshot it just took, strictly: any claim with more than one folder stops the rebuild
# while prod is still up, even where the etcd record could settle it afterwards.
plan() { env_dev "$1" "${@:2}" "$bin/c1-restore-volumes.sh" plan; }
if out=$(plan 20 RESTORE_SOURCE_HOST=ci-prod3 RESTORE_PLAN_STRICT=1 2>&1); then echo "$out"; fail "the strict plan passed with three folders for one claim"; fi
grep -q 'more than one folder for the same claim: openbao/data-openbao-0 <- ' <<< "$out" || { echo "$out"; fail "the strict plan failed for another reason"; }
grep -q "$A" <<< "$out" && grep -q "$B" <<< "$out" && grep -q "$C" <<< "$out" || fail "the strict plan did not name all three folders"
if out=$(plan 21 RESTORE_SOURCE_HOST=ci-prod2 RESTORE_PLAN_STRICT=1 2>&1); then fail "the strict plan passed with two folders for one claim"; fi
ok "the strict plan fails on two and on three folders for one claim, naming every folder, and changes nothing"
# A clean snapshot: one folder per claim.
seed no
rm -rf "$data/${A}_openbao_data-openbao-0"
BACKUP_HOST=ci-clean BACKUP_STATE=$work/prod-state-clean BACKUP_VOLUME_PATHS=$data "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the clean backup failed"
out=$(plan 22 RESTORE_SOURCE_HOST=ci-clean RESTORE_PLAN_STRICT=1 2>&1) || { echo "$out"; fail "the strict plan failed on a clean snapshot"; }
grep -qP '^PASS: plan: snapshot [0-9a-f]{64}: 2 folders map to 2 claims, no claim has more than one folder$' <<< "$out" || { echo "$out"; fail "the plan's PASS line is not as expected"; }
ok "the strict plan passes on a snapshot with one folder per claim, and prints the full snapshot ID"
out=$(plan 23 RESTORE_SOURCE_HOST=ci-prod3 2>&1) || { echo "$out"; fail "the plan without strict failed although the etcd record settles it"; }
grep -q 'settled by the etcd record' <<< "$out" || fail "the plan did not say the etcd record settled it"
ok "without strict, the plan passes where the etcd record settles the claim and says so"
mkdir -p "$data/pvc-cccc_media" && echo x > "$data/pvc-cccc_media/f"
BACKUP_HOST=ci-bad BACKUP_STATE=$work/prod-state-bad BACKUP_VOLUME_PATHS=$data "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the bad-name backup failed"
if out=$(plan 24 RESTORE_SOURCE_HOST=ci-bad RESTORE_PLAN_STRICT=1 2>&1); then fail "the strict plan passed with a name it can't map"; fi
grep -q 'not <namespace>/<claim>' <<< "$out" || { echo "$out"; fail "the plan failed for another reason on a name it can't map"; }
ok "the plan fails on a folder name it can't map"

echo "== 5. the etcd snapshot of the control plane, and the forget hold"
# Another host's etcd snapshot, taken nearer in time and saying another volume: ignored once the control plane is named.
seed yes
etcd_backup                                   # ci-cp: the claim is bound to B
sleep 3
e put /registry/persistentvolumeclaims/openbao/data-openbao-0 "bytes volumeName=$C" >/dev/null
BACKUP_HOST=ci-other BACKUP_STATE=$work/other-state ETCDCTL_ENDPOINTS=$ep ETCD_CACERT='' KUBE_DIR=$work/kube "$bin/c1-backup-etcd.sh" > "$work/etcd-other.log" 2>&1 || { cat "$work/etcd-other.log"; fail "the other host's etcd backup failed"; }
BACKUP_HOST=ci-prod5 BACKUP_STATE=$work/prod-state5 BACKUP_VOLUME_PATHS=$data "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the fifth volume backup failed"
fresh
env_dev 30 RESTORE_SOURCE_HOST=ci-prod5 RESTORE_ETCD_HOST=ci-cp "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1 || { cat "$work/r.log"; fail "the restore naming the control plane failed"; }
[ "$(cat "$dev/openbao/data-openbao-0/vault.db")" = generation-b ] || fail "the other host's etcd snapshot was used although the control plane was named"
fresh
env_dev 31 RESTORE_SOURCE_HOST=ci-prod5 "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1 || { cat "$work/r.log"; fail "the restore with no host named failed"; }
[ "$(cat "$dev/openbao/data-openbao-0/vault.db")" = generation-c ] || fail "with no host named, the nearest etcd snapshot was not the other host's (the test does not show the filter)"
ok "the etcd snapshot comes from the named control plane even when another host's is nearer in time (and the test shows it would otherwise be taken)"

# The forget hold: with it set a backup forgets nothing; without it, retention runs as before.
hold_env=(BACKUP_HOST=ci-hold "BACKUP_STATE=$work/hold-state" "BACKUP_VOLUME_PATHS=$data" BACKUP_KEEP_DAILY=1 BACKUP_KEEP_WEEKLY=0 BACKUP_KEEP_MONTHLY=0)
count() { "$bin/restic" snapshots --json --host ci-hold --tag volumes | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
env "${hold_env[@]}" "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the first hold backup failed"
mkdir -p "$work/hold-state" && echo held > "$work/hold-state/forget-hold"
env "${hold_env[@]}" "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the held backup failed"
env "${hold_env[@]}" "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the second held backup failed"
grep -q 'retention skipped' "$work/vol.log" || fail "the held backup did not say it skipped the retention"
[ "$(count)" = 3 ] || fail "a backup under the hold forgot a snapshot ($(count) left, want 3)"
rm -f "$work/hold-state/forget-hold"
env "${hold_env[@]}" "$bin/c1-backup-volumes.sh" > "$work/vol.log" 2>&1 || fail "the backup after the hold failed"
[ "$(count)" = 1 ] || fail "retention did not run once the hold was released ($(count) left, want 1)"
ok "a backup under the forget hold forgets nothing; once it is released the retention runs as before"
grep -q 'forget-hold' "$role/tasks/restore.yml" && grep -q 'state: absent' "$role/tasks/restore_check.yml" && grep -q 'forget-hold' "$role/tasks/restore_check.yml" || fail "the role does not set and release the hold"
ok "the restore stage sets the hold on every node and the checks stage releases it"

echo "restore-pv: $pass checks passed"
