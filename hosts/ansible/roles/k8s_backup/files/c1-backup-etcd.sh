#!/usr/bin/env bash
# Back up c1's etcd off the box (role k8s_backup, runbook docs/runbooks/back-up-c1-off-box.md).
# Runs on the control-plane node as root, from timer c1-backup-etcd.timer.
#
# One restic snapshot, tag "etcd", holds:
#   etcd/snapshot.db         etcdctl snapshot save, checked with etcdutl snapshot status
#   etcd/status.json         that status (hash, revision, total keys, size)
#   kubernetes/pki/          the cluster's CAs and keys, so a rebuilt node can take the snapshot
#   kubernetes/manifests/    the static pod manifests (etcd's name and peer URL are in etcd.yaml)
#   kubernetes/kubeadm-config.yaml   ConfigMap kube-system/kubeadm-config, when kubectl can read it
# Not in it: /etc/kubernetes/enc, the key for Secrets at rest. It stays with the owner (runbook
# step 8a), so a stolen backup and its password still can't read a Secret.
#
# Settings (besides those in c1-backup-lib.sh):
#   ETCDCTL_ENDPOINTS  default https://127.0.0.1:2379
#   ETCD_CACERT, ETCD_CERT, ETCD_KEY   default kubeadm's healthcheck client in /etc/kubernetes/pki/etcd;
#                      set ETCD_CACERT to an empty string for a plain-HTTP etcd (CI only)
#   KUBE_DIR           default /etc/kubernetes
set -euo pipefail
# shellcheck source=c1-backup-lib.sh
. "$(dirname "$0")/c1-backup-lib.sh"
backup_lib_init

ETCDCTL=${ETCDCTL:-$BACKUP_BIN/etcdctl}
ETCDUTL=${ETCDUTL:-$BACKUP_BIN/etcdutl}
KUBE_DIR=${KUBE_DIR:-/etc/kubernetes}
export ETCDCTL_ENDPOINTS=${ETCDCTL_ENDPOINTS:-https://127.0.0.1:2379}
tls=()
if [ -n "${ETCD_CACERT-$KUBE_DIR/pki/etcd/ca.crt}" ]; then
  tls=(--cacert "${ETCD_CACERT:-$KUBE_DIR/pki/etcd/ca.crt}"
       --cert "${ETCD_CERT:-$KUBE_DIR/pki/etcd/healthcheck-client.crt}"
       --key "${ETCD_KEY:-$KUBE_DIR/pki/etcd/healthcheck-client.key}")
fi

work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-backup-etcd.XXXXXX")
trap 'rm -rf "$work"' EXIT
chmod 0700 "$work"
mkdir -p "$work/etcd" "$work/kubernetes"

log "etcd snapshot from $ETCDCTL_ENDPOINTS"
"$ETCDCTL" "${tls[@]}" snapshot save "$work/etcd/snapshot.db" >/dev/null
"$ETCDUTL" snapshot status "$work/etcd/snapshot.db" -w json > "$work/etcd/status.json"
log "snapshot: $(cat "$work/etcd/status.json")"

for part in pki manifests; do
  [ -d "$KUBE_DIR/$part" ] && cp -a "$KUBE_DIR/$part" "$work/kubernetes/$part"
done
if command -v kubectl >/dev/null 2>&1 && [ -r "$KUBE_DIR/admin.conf" ]; then
  kubectl --kubeconfig "$KUBE_DIR/admin.conf" -n kube-system get configmap kubeadm-config -o yaml \
    > "$work/kubernetes/kubeadm-config.yaml" || log "kubeadm-config not read; carrying on without it"
fi

restic_ensure_repo
# Relative paths, so a restore lands as etcd/ and kubernetes/ under the target folder.
(cd "$work" && "$RESTIC" backup --host "$BACKUP_HOST" --tag etcd --tag c1 etcd kubernetes)
restic_retention etcd
log "etcd backup done"
