#!/usr/bin/env bash
# End-to-end test of the c1 backup and restore-test scripts (role k8s_backup), on one machine, with
# no cluster: the scripts the role installs run against a real etcd and a local restic repository.
#
#   1. etcd 3.7.0, the version c1 runs, holds test keys; c1-backup-etcd.sh backs it up with the
#      etcdctl and etcdutl the role installs (v3.7.2). c1-restore-test-etcd.sh must pass (TASK-0094).
#   2. The same restore test with a key that isn't there must fail.
#   3. c1-backup-volumes.sh backs up two folders and a PostgreSQL dump (stand-in crictl); the source
#      changes afterwards; c1-restore-test-volumes.sh must pass, a full restore must equal the source
#      as backed up, and a dump that does not finish must fail the backup.
#   4. Keycloak's PostgreSQL image (the one role k8s_identity runs, under Docker with the kubelet's
#      labels, reached through a stand-in for crictl): a real pg_dumpall goes into the snapshot, and
#      the runbook's "Restore Keycloak's database" steps load it into a new database whose password
#      changed since the dump: every row comes back, and the new password still signs in.
#   5. One pack file in the repository damaged: the volume restore test must fail.
#   6. Dev's restore (c1-restore-volumes.sh): prod's folders, named as local-path names them on c1
#      (pvc-<uid>_<namespace>_<claim>), come back whole at <namespace>/<claim> from a repository it
#      can't write to; a second run does nothing, check catches a changed restore, owner checks
#      one folder as the checks stage does, and it refuses a folder that already holds data, two
#      folders for one claim and a name it can't map.
#
# Tools come from their GitHub releases, each checked against a SHA-256: the versions and sums the
# role installs are read from its defaults/main.yml, so CI tests what goes on the nodes.
# Usage: .github/hosts-check/tests/test_backup.sh   (needs curl, python3 with PyYAML, bunzip2, tar,
# docker)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
role=$root/hosts/ansible/roles/k8s_backup
work=$(mktemp -d)
pg_containers=()
cleanup() {
  [ -n "${etcd_pid:-}" ] && kill "$etcd_pid" 2>/dev/null
  [ ${#pg_containers[@]} -gt 0 ] && docker rm -f "${pg_containers[@]}" >/dev/null 2>&1
  # Section 6 makes a repository read-only; a failure there must not leave it undeletable.
  chmod -R u+w "$work" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# etcd's server at the version c1 runs (runbook step 17: etcd 3.7.0-0), only for this test.
CLUSTER_ETCD_VERSION=3.7.0
CLUSTER_ETCD_SHA256=b05cb07f5686dab8f9cdab89986b44f0dd24aaf5c627176aff325e21fa56f9f0

read -r restic_v restic_sum etcd_v etcd_sum < <(python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(d["k8s_backup_restic_version"], d["k8s_backup_restic_sha256"], d["k8s_backup_etcd_version"], d["k8s_backup_etcd_sha256"])
' "$role/defaults/main.yml")

fetch() { # url sha256 out
  # Same retry policy as run.sh and docs.yml: GitHub release downloads return 504s for minutes at a time.
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 15 -o "$3" "$1"
  echo "$2  $3" | sha256sum --check --quiet
}
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
# sed -n 1p, not head -1: head exits early and, with pipefail, a writer still printing dies of
# SIGPIPE (exit 141 in CI on 2026-11-09).
"$bin/restic" version
"$bin/etcdutl" version | sed -n 1p
"$work/cluster/etcd" --version | sed -n 1p

# What the env file gives the scripts on a node, here set directly.
export BACKUP_BIN=$bin BACKUP_HOST=ci-node BACKUP_STATE=$work/state TMPDIR=$work
export CENTRAL_HUB_BACKUP_ENV=$work/none.env
export RESTIC_REPOSITORY=$work/repo RESTIC_PASSWORD=ci-only-not-a-secret RESTIC_CACHE_DIR=$work/cache

pass=0
ok() { echo "ok - $*"; pass=$((pass + 1)); }
fail() { echo "not ok - $*" >&2; exit 1; }

echo "== 1. etcd backup and restore test"
"$work/cluster/etcd" --name ci --data-dir "$work/etcd-data" \
  --listen-client-urls http://127.0.0.1:12379 --advertise-client-urls http://127.0.0.1:12379 \
  --listen-peer-urls http://127.0.0.1:12380 --initial-advertise-peer-urls http://127.0.0.1:12380 \
  --initial-cluster ci=http://127.0.0.1:12380 > "$work/etcd.log" 2>&1 &
etcd_pid=$!
for _ in $(seq 60); do "$bin/etcdctl" --endpoints http://127.0.0.1:12379 endpoint health >/dev/null 2>&1 && break; sleep 1; done
e() { "$bin/etcdctl" --endpoints http://127.0.0.1:12379 "$@"; }
e put /registry/namespaces/kube-system '{"kind":"Namespace"}' >/dev/null
for i in $(seq 200); do e put "/registry/configmaps/ci/cm-$i" "value-$i" >/dev/null; done
# A fake /etc/kubernetes: the script copies pki/ and manifests/ into the snapshot.
mkdir -p "$work/kube/pki/etcd" "$work/kube/manifests"
echo "fake-ca" > "$work/kube/pki/ca.crt"
echo "fake-manifest" > "$work/kube/manifests/etcd.yaml"
ETCDCTL_ENDPOINTS=http://127.0.0.1:12379 ETCD_CACERT='' KUBE_DIR=$work/kube "$bin/c1-backup-etcd.sh"
ok "c1-backup-etcd.sh backed up etcd $CLUSTER_ETCD_VERSION with etcdctl $etcd_v"
# The listing goes in a variable first: grep -q stops at the first match, and with pipefail a
# restic still printing dies of SIGPIPE and fails the check (seen locally, 2026-11-09).
listing=$("$bin/restic" ls latest --tag etcd)
grep -qx '/kubernetes/pki/ca.crt' <<< "$listing" || fail "pki/ca.crt is not in the snapshot"
ok "the snapshot holds kubernetes/pki"
out=$("$bin/c1-restore-test-etcd.sh")
echo "$out"
grep -q 'PASS: etcd restore test' <<< "$out" || fail "c1-restore-test-etcd.sh did not pass"
grep -q ' 201 keys under /' <<< "$out" || fail "the restored etcd does not hold the 201 test keys"
ok "c1-restore-test-etcd.sh restored it with etcdutl $etcd_v and found all 201 keys"

echo "== 2. the restore test fails on a missing key"
if out=$(CHECK_KEY=/registry/namespaces/not-there "$bin/c1-restore-test-etcd.sh" 2>&1); then
  fail "c1-restore-test-etcd.sh passed with a missing key"
fi
grep -q 'FAIL: key /registry/namespaces/not-there is missing' <<< "$out" || { echo "$out"; fail "it failed for another reason"; }
ok "c1-restore-test-etcd.sh fails when CHECK_KEY is missing"

echo "== 3. volume backup and restore test"
v1=$work/data/local-path/pvc-1_media_config
v2=$work/data/identity-postgres
mkdir -p "$v1/sub" "$v2"
head -c 3000000 /dev/urandom > "$v1/sub/blob.bin"
echo "jellyfin settings" > "$v1/settings.xml"
head -c 100000 /dev/urandom > "$v2/16384"
export BACKUP_VOLUME_PATHS="$work/data/local-path $v2 $work/data/not-there"
# A stand-in for crictl with one running PostgreSQL container, whose pg_dumpall prints a dump
# shaped like the real one (or one cut short, in mode "short").
cat > "$work/crictl" <<'CRI'
#!/usr/bin/env bash
case "$1" in
  ps) echo '{"containers":[{"id":"abc123","labels":{"io.kubernetes.pod.namespace":"identity","io.kubernetes.pod.name":"sso-postgres-0"}}]}' ;;
  exec) [ "$2" = abc123 ] || exit 1
        printf -- '--\n-- PostgreSQL database cluster dump\n--\nCREATE ROLE keycloak;\n'
        [ "$(cat "$0.mode" 2>/dev/null)" = short ] && exit 1
        printf -- '\n--\n-- PostgreSQL database cluster dump complete\n--\n\n' ;;
  *) exit 2 ;;
esac
CRI
chmod +x "$work/crictl"
export BACKUP_CRICTL=$work/crictl
"$bin/c1-backup-volumes.sh"
ok "c1-backup-volumes.sh backed up two folders and skipped the missing one"
cp -a "$work/data" "$work/as-backed-up"
echo "changed after the backup" >> "$v1/settings.xml"
out=$("$bin/c1-restore-test-volumes.sh")
echo "$out"
grep -q 'PASS: volume restore test, 2 folders, 1 database dumps' <<< "$out" || fail "c1-restore-test-volumes.sh did not pass"
grep -q 'identity_sso-postgres-0.sql: complete' <<< "$out" || fail "the database dump was not checked"
ok "c1-restore-test-volumes.sh passed, canaries match, the database dump came back complete"
"$bin/restic" restore latest --host ci-node --tag volumes --target "$work/full" >/dev/null
diff -r "$work/as-backed-up" "$work/full$work/data" || fail "a full restore differs from the source at backup time"
ok "a full restore equals the folders as they were backed up"
echo short > "$work/crictl.mode"
if "$bin/c1-backup-volumes.sh" > "$work/short.log" 2>&1; then fail "a cut-short database dump passed"; fi
grep -q 'a database dump failed; the files were backed up' "$work/short.log" || { cat "$work/short.log"; fail "wrong failure"; }
rm "$work/crictl.mode"
ok "a database dump that does not finish fails the volume backup"

echo "== 4. a real PostgreSQL: the dump restores by the runbook and keeps the current password"
pg_image=$(python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["k8s_identity_postgres_image"])' \
  "$root/hosts/ansible/roles/k8s_identity/defaults/main.yml")
for try in 1 2 3 4 5; do
  docker pull -q "$pg_image" >/dev/null && break
  [ "$try" = 5 ] && fail "could not pull $pg_image"
  sleep $((try * 15))
done
# A database as role k8s_identity runs it: uid 999, PGDATA in a subfolder, the kubelet's labels.
pg_run() { # container-name password [docker run flags]
  local name=$1 password=$2
  shift 2
  pg_containers+=("$name")
  docker run -d --name "$name" --user 999:999 -e POSTGRES_DB=keycloak -e POSTGRES_USER=keycloak \
    -e POSTGRES_PASSWORD="$password" -e PGDATA=/var/lib/postgresql/data/pgdata "$@" "$pg_image" >/dev/null
  for _ in $(seq 60); do
    docker exec "$name" pg_isready -h 127.0.0.1 -U keycloak -d keycloak >/dev/null 2>&1 && return 0
    sleep 1
  done
  fail "PostgreSQL in $name did not start"
}
# Signs in over the network with a password, as Keycloak's pod does. Inside the container,
# 127.0.0.1 is trusted without one, so this runs from a second container.
pg_login() { # container-name password
  local ip
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1")
  docker run --rm -e PGPASSWORD="$2" "$pg_image" psql -h "$ip" -U keycloak -d keycloak -tAc 'select count(*) from realm'
}
# crictl ps -o json and crictl exec, answered from Docker's containers and their kubelet labels.
cat > "$work/crictl-docker" <<'CRI'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  ps) ids=$(docker ps -q --no-trunc --filter label=io.kubernetes.container.name=postgres)
      if [ -z "$ids" ]; then echo '{"containers": []}'; exit 0; fi
      # shellcheck disable=SC2086  # one argument per container ID
      docker inspect $ids | python3 -c 'import json, sys
print(json.dumps({"containers": [{"id": c["Id"], "labels": c["Config"]["Labels"]} for c in json.load(sys.stdin)]}))' ;;
  exec) shift; exec docker exec "$@" ;;
  *) exit 2 ;;
esac
CRI
chmod +x "$work/crictl-docker"
export BACKUP_CRICTL=$work/crictl-docker
db=ci-backup-db-$$
pg_run "$db" password-at-dump --label io.kubernetes.pod.namespace=identity \
  --label io.kubernetes.pod.name=sso-postgres-0 --label io.kubernetes.container.name=postgres
docker exec "$db" psql -q -U keycloak -d keycloak -v ON_ERROR_STOP=1 \
  -c "create table realm (id int primary key, name text)" \
  -c "insert into realm select g, 'realm-' || g from generate_series(1, 500) g"
"$bin/c1-backup-volumes.sh"
out=$("$bin/c1-restore-test-volumes.sh")
echo "$out"
grep -q 'identity_sso-postgres-0.sql: complete' <<< "$out" || fail "the restore test did not check the real dump"
ok "c1-backup-volumes.sh dumped a real PostgreSQL through crictl, and the restore test found the dump complete"
# Runbook "Restore Keycloak's database", steps 2 and 3, with docker exec in place of kubectl exec,
# into a new database whose password changed after the dump (a rotated or rebuilt Secret).
"$bin/restic" restore latest --host ci-node --tag volumes --include "$BACKUP_STATE/db-dumps" \
  --target "$work/db-restore" >/dev/null
dump=$work/db-restore$BACKUP_STATE/db-dumps/identity_sso-postgres-0.sql
if grep -q "^ALTER ROLE .* PASSWORD " "$dump"; then
  fail "the dump holds a role's password"
fi
db2=ci-backup-db2-$$
pg_run "$db2" password-now
# shellcheck disable=SC2016  # $POSTGRES_USER is the container's
docker exec -i "$db2" sh -c 'dropdb -U "$POSTGRES_USER" --if-exists keycloak'
# shellcheck disable=SC2016
docker exec -i "$db2" sh -c 'psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=0' < "$dump" > "$work/load.log" 2>&1
if grep -q FATAL "$work/load.log"; then cat "$work/load.log"; fail "psql stopped with FATAL"; fi
rows=$(pg_login "$db2" password-now 2>&1) || { echo "$rows"; fail "the database's current password no longer signs in after the restore"; }
[ "$rows" = 500 ] || fail "the restored database has $rows rows, want 500"
ok "the runbook's restore brings back all 500 rows, and the current password still signs in"
docker rm -f "$db" "$db2" >/dev/null
unset BACKUP_CRICTL

echo "== 5. a damaged repository fails the volume restore test"
pack=$(find "$RESTIC_REPOSITORY/data" -type f -size +1M -print -quit)
[ -n "$pack" ] || fail "no pack file to damage"
chmod u+w "$pack"
printf 'XXXXXXXX' | dd of="$pack" bs=1 seek=4096 conv=notrunc status=none
rm -rf "$RESTIC_CACHE_DIR"
if out=$(RESTORE_READ_DATA_SUBSET=100% "$bin/c1-restore-test-volumes.sh" 2>&1); then
  fail "c1-restore-test-volumes.sh passed on a damaged repository"
fi
grep -qi 'pack .* contains .* errors\|ciphertext verification failed\|Fatal: repository contains errors' <<< "$out" \
  || { echo "$out"; fail "it failed for another reason"; }
ok "c1-restore-test-volumes.sh fails on a damaged pack file"

echo "== 6. dev's restore of prod's newest volume snapshot (c1-restore-volumes.sh, TASK-0240)"
# A repository of its own: section 5 damaged the first one.
export RESTIC_REPOSITORY=$work/repo-restore
prod_path=$work/c1-data/local-path
# Prod's folders as c1 names them (local-path's default), and one already in <namespace>/<claim>.
loki=pvc-7f3e2a10-1b2c-4d5e-8f90-a1b2c3d4e5f6_logging_storage-loki-0
jf=pvc-0b1c2d3e-4f50-6172-8394-a5b6c7d8e9f0_media_jellyfin-config
jm=pvc-11111111-2222-3333-4444-555555555555_media_jellyfin-media
mkdir -p "$prod_path/$jf/data" "$prod_path/$loki/chunks" "$prod_path/$jm" "$prod_path/monitoring/grafana"
echo "<ServerConfiguration/>" > "$prod_path/$jf/system.xml"
head -c 300000 /dev/urandom > "$prod_path/$jf/data/library.db"
for i in $(seq 1 40); do echo "chunk $i" > "$prod_path/$loki/chunks/$i"; done
ln -s system.xml "$prod_path/$jf/link.xml"
echo "{}" > "$prod_path/monitoring/grafana/grafana.db"
BACKUP_HOST=ci-prod BACKUP_STATE=$work/prod-state BACKUP_VOLUME_PATHS=$prod_path \
  "$bin/c1-backup-volumes.sh" > "$work/prod-backup.log" 2>&1 || { cat "$work/prod-backup.log"; fail "prod's volume backup failed"; }
# What dev must hold: the same folders, each at <namespace>/<claim>.
want_tree=$work/prod-as-backed-up
mkdir -p "$want_tree/media" "$want_tree/logging"
cp -a "$prod_path/$jf" "$want_tree/media/jellyfin-config"
cp -a "$prod_path/$jm" "$want_tree/media/jellyfin-media"
cp -a "$prod_path/$loki" "$want_tree/logging/storage-loki-0"
cp -a "$prod_path/monitoring" "$want_tree/monitoring"
cp -a "$prod_path/.central-hub-backup-canary" "$want_tree/"
# Dev starts with an empty data disk.
rm -rf "$prod_path" && mkdir -p "$prod_path"
# Read-only: with the repository unwritable, any lock or other write would fail the restore.
repo_before=$(cd "$RESTIC_REPOSITORY" && find . -type f | sort | xargs sha256sum | sha256sum)
chmod -R a-w "$RESTIC_REPOSITORY"
dev_env=(BACKUP_HOST=ci-dev "BACKUP_STATE=$work/dev-state" RESTORE_SOURCE_HOST=ci-prod "RESTORE_PATH=$prod_path" RESTORE_REQUIRE_MOUNT=)
out=$(env "${dev_env[@]}" "$bin/c1-restore-volumes.sh" restore 2>&1) || { echo "$out"; fail "the dev restore failed"; }
echo "$out"
grep -q '^PASS: restored snapshot .* 4 folders, 43 files' <<< "$out" || fail "the restore did not report 4 folders and 43 files"
grep -qP '^folder\tmedia/jellyfin-config\t2\t' <<< "$out" || fail "the restore did not log jellyfin-config's count"
grep -qx "mapped $jf -> media/jellyfin-config" <<< "$out" || fail "the restore did not log jellyfin-config's mapping"
diff -r "$want_tree" "$prod_path" || fail "the restored folders differ from prod's as backed up"
[ ! -e "$work/c1-data/.c1-restore-stage" ] || fail "the staging folder was left behind"
repo_after=$(cd "$RESTIC_REPOSITORY" && find . -type f | sort | xargs sha256sum | sha256sum)
[ "$repo_before" = "$repo_after" ] || fail "the restore changed the repository"
ok "c1-restore-volumes.sh restored every folder at <namespace>/<claim> from an unwritable repository, counts and canary match, the repository is unchanged"

out=$(env "${dev_env[@]}" "$bin/c1-restore-volumes.sh" restore 2>&1) || { echo "$out"; fail "a second restore run failed"; }
grep -q '^ALREADY: ' <<< "$out" || fail "a second run did not say ALREADY"
out=$(env "${dev_env[@]}" "$bin/c1-restore-volumes.sh" check 2>&1) || { echo "$out"; fail "check failed after the restore"; }
grep -q 'PASS: restore of snapshot .* still in place, 4 folders, canary matches' <<< "$out" || { echo "$out"; fail "check did not pass"; }
ok "a second run does nothing, and check passes"

echo "changed" > "$prod_path/.central-hub-backup-canary"
if env "${dev_env[@]}" "$bin/c1-restore-volumes.sh" check > /dev/null 2>&1; then fail "check passed with a wrong canary"; fi
rm -rf "$prod_path/logging/storage-loki-0"
cp "$work/prod-as-backed-up/.central-hub-backup-canary" "$prod_path/"
if env "${dev_env[@]}" "$bin/c1-restore-volumes.sh" check > /dev/null 2>&1; then fail "check passed with a folder gone"; fi
ok "check fails on a wrong canary and on a missing folder"

# owner: the checks stage's test of one folder. local-path makes the folder as root, mode 0777;
# the app's files inside belong to its user (run 18, 2026-11-10: prod and dev both so). Changing
# owners needs root: CI's runner has passwordless sudo.
jcfg=$prod_path/media/jellyfin-config
own() { env "${dev_env[@]}" "$bin/c1-restore-volumes.sh" owner "$@"; }
if [ "$(id -u)" = 0 ]; then asroot=(); elif sudo -n true 2>/dev/null; then asroot=(sudo -n); else asroot=(none); fi
if [ "${asroot[0]:-}" != none ]; then
  "${asroot[@]}" chown -R -h 1000:1000 "$jcfg"
  "${asroot[@]}" chown 0:0 "$jcfg"
  "${asroot[@]}" chmod 0777 "$jcfg"
  out=$(own media/jellyfin-config 1000 2>&1) || { echo "$out"; fail "owner failed on a folder as local-path makes it"; }
  grep -q '^PASS: .* all 3 entries in it belong to uid 1000' <<< "$out" || { echo "$out"; fail "owner did not pass"; }
  "${asroot[@]}" chown 0:0 "$jcfg/system.xml"
  if out=$(own media/jellyfin-config 1000 2>&1); then fail "owner passed with a file owned by root inside"; fi
  grep -q 'not owned by uid 1000: system.xml (uid 0)' <<< "$out" || { echo "$out"; fail "it failed for another reason"; }
  "${asroot[@]}" chown 1000:1000 "$jcfg/system.xml" "$jcfg"
  if out=$(own media/jellyfin-config 1000 2>&1); then fail "owner passed with the folder owned by the app, not root"; fi
  grep -q 'is 1000:1000 777 (owner:group mode), local-path makes it 0:0 777' <<< "$out" || { echo "$out"; fail "it failed for another reason"; }
  "${asroot[@]}" chown 0:0 "$jcfg"
  "${asroot[@]}" chmod 0755 "$jcfg"
  if out=$(own media/jellyfin-config 1000 2>&1); then fail "owner passed with mode 755"; fi
  grep -q 'is 0:0 755 (owner:group mode)' <<< "$out" || { echo "$out"; fail "it failed for another reason"; }
  "${asroot[@]}" mkdir -m 0777 "$prod_path/media/empty-claim"
  if out=$(own media/empty-claim 1000 2>&1); then fail "owner passed on an empty folder"; fi
  grep -q 'is empty' <<< "$out" || { echo "$out"; fail "it failed for another reason"; }
  # Back to this user, so the later cases and the cleanup can write.
  "${asroot[@]}" rmdir "$prod_path/media/empty-claim"
  "${asroot[@]}" chown -R -h "$(id -u):$(id -g)" "$jcfg"
  "${asroot[@]}" chmod 0777 "$jcfg"
  out=$(own media/not-here 1000 2>&1) || { echo "$out"; fail "owner failed on a node without the folder"; }
  grep -q '^SKIP: ' <<< "$out" || fail "a node without the folder did not SKIP"
  ok "owner passes on a folder that is 0:0 777 with the app's files inside, fails on a file of another user, an app-owned folder, mode 755 and an empty folder, and skips a node without it"
else
  echo "   owner cases skipped: they change owners, which needs root or passwordless sudo"
fi

# Never over data it didn't restore: a non-empty folder with no record of this restore.
if env "${dev_env[@]}" BACKUP_STATE="$work/dev-state-2" "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1; then
  fail "the restore wrote into a folder that already holds data"
fi
grep -q 'is not empty' "$work/r.log" || { cat "$work/r.log"; fail "it failed for another reason"; }
ok "the restore refuses a folder that already holds data"

# Snapshots it can't map stop it before anything is written: two folders for one claim (a claim
# deleted and made again, its old folder kept), and a folder that is neither naming.
chmod -R u+w "$RESTIC_REPOSITORY"
bad_path=$work/bad-data/local-path
for case in dup unknown; do
  rm -rf "$bad_path" && mkdir -p "$bad_path"
  if [ "$case" = dup ]; then
    mkdir -p "$bad_path/pvc-aaaa_media_jellyfin-config" "$bad_path/pvc-bbbb_media_jellyfin-config"
    want=DUPLICATE
  else
    mkdir -p "$bad_path/pvc-cccc_media"
    want=UNKNOWN
  fi
  find "$bad_path" -mindepth 1 -maxdepth 1 -type d -exec sh -c 'echo x > "$1/f"' _ {} \;
  BACKUP_HOST=ci-$case BACKUP_STATE=$work/$case-state BACKUP_VOLUME_PATHS=$bad_path \
    "$bin/c1-backup-volumes.sh" > /dev/null 2>&1 || fail "the $case backup failed"
  rm -rf "$bad_path" && mkdir -p "$bad_path"
  if env BACKUP_HOST=ci-dev BACKUP_STATE="$work/dev-state-$case" RESTORE_SOURCE_HOST=ci-$case RESTORE_PATH="$bad_path" RESTORE_REQUIRE_MOUNT= \
    "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1; then
    fail "the restore took a snapshot it can't map ($case)"
  fi
  grep -q "$want" "$work/r.log" || { cat "$work/r.log"; fail "it failed for another reason ($case)"; }
  [ -z "$(ls -A "$bad_path")" ] || fail "the refused restore left files behind ($case)"
done
ok "the restore refuses two folders for one claim and a name it can't map, and writes nothing"

if env BACKUP_HOST=ci-dev BACKUP_STATE="$work/dev-state-4" RESTORE_SOURCE_HOST=no-such-host RESTORE_PATH="$work/none" RESTORE_REQUIRE_MOUNT= \
  "$bin/c1-restore-volumes.sh" restore > "$work/r.log" 2>&1; then
  fail "the restore passed with no snapshot of that host"
fi
grep -q "no volume snapshot of host no-such-host" "$work/r.log" || { cat "$work/r.log"; fail "it failed for another reason"; }
out=$(env BACKUP_HOST=ci-dev BACKUP_STATE="$work/dev-state-5" RESTORE_SOURCE_HOST=ci-prod RESTORE_PATH="$work/nodisk/local-path" \
  "$bin/c1-restore-volumes.sh" restore 2>&1) || { echo "$out"; fail "a node without the data disk failed"; }
grep -q '^SKIP: ' <<< "$out" || fail "a node without the data disk did not SKIP"
ok "the restore fails with no snapshot of the host, and skips a node without its data disk"

echo "backup: $pass checks passed"
