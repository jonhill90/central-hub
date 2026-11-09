#!/usr/bin/env bash
# Rebuild one cluster's Kubernetes layer from this repository in one command: node VMs, the
# cluster, Argo CD and its apps, then checks. Proxmox, OPNsense, DNS and the backup target stay
# as they are (the owner's card, 2026-11-09 23:21 UTC). It stops at the first stage that fails.
#
# Usage: hosts/rebuild-k8s.sh <env-dir> [--teardown] [--only <stage>[,<stage>...]]
#
# <env-dir> is a private folder on the controller (mode 0700), outside the repository. It holds
# rebuild.env (mode 0600), which sets:
#   ENV_NAME      dev or prod
#   VM_ID_MIN     lowest VM ID this env may touch (dev: 250)
#   VM_ID_MAX     highest VM ID this env may touch (dev: 257; 258 and 259 are the jumpboxes)
#   TFVARS        the k8s run folder's tfvars for this env
#   TFSTATE       its OpenTofu state file
#   TOFU_ENV      a file that exports PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (and _INSECURE)
#   INVENTORY     the Ansible inventory for this env
#   KUBECONFIG    the kubeconfig for this env's cluster
#   STAGES        optional: the stages to run, in order (default below)
#   PRE_VMS_HOOK  optional: a command run before the VMs are made (Proxmox /vms ACLs, R4 step 0)
#   RESTORE_HOOK  optional: the restore command for stage `restore`
#   APPS_TIMEOUT  optional: seconds to wait for every Argo CD app to be Synced and Healthy (1200)
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
# gateway runs after apps: with k8s_gateway_by_argocd true, Argo CD makes the Gateway, and the
# playbook's "programmed" wait and smoke test then check it.
default_stages="vms cluster storage gitops apps gateway certs identity ui restore checks"

die() { echo "rebuild: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: $0 <env-dir> [--teardown] [--only <stage>[,<stage>...]]"
env_dir=$1; shift
teardown=false; only=""
while [ $# -gt 0 ]; do
  case $1 in
    --teardown) teardown=true ;;
    --only) shift; only=${1:-} ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[ -f "$env_dir/rebuild.env" ] || die "$env_dir/rebuild.env is missing"
[ "$(stat -c %a "$env_dir" 2>/dev/null || stat -f %Lp "$env_dir")" = 700 ] || die "$env_dir must be mode 0700"
# shellcheck source=/dev/null
. "$env_dir/rebuild.env"
for v in ENV_NAME VM_ID_MIN VM_ID_MAX TFVARS TFSTATE TOFU_ENV INVENTORY KUBECONFIG; do
  [ -n "${!v:-}" ] || die "$v is not set in rebuild.env"
done
export KUBECONFIG
case $ENV_NAME in dev|prod) ;; *) die "ENV_NAME must be dev or prod" ;; esac

# Every node's VM ID in the tfvars must sit in this env's range, so a dev run can't touch prod's
# VMs. template_vm_id is left out: a dev cluster clones a template another state owns.
ids=$(grep -Eo '(^|[^_[:alnum:]])vm_id[[:space:]]*=[[:space:]]*[0-9]+' "$TFVARS" | grep -Eo '[0-9]+$' || true)
[ -n "$ids" ] || die "no vm_id found in $TFVARS"
for id in $ids; do
  [ "$id" -ge "$VM_ID_MIN" ] && [ "$id" -le "$VM_ID_MAX" ] || die "vm_id $id is outside $VM_ID_MIN-$VM_ID_MAX"
done
if [ "$ENV_NAME" = dev ]; then
  grep -Eq 'node_vnet[[:space:]]*=[[:space:]]*"dev"' "$TFVARS" || die "a dev run needs node_vnet = \"dev\""
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$env_dir/logs"
log="$env_dir/logs/rebuild-$stamp.log"
raw="$env_dir/logs/rebuild-$stamp.raw"
: > "$log"; : > "$raw"; chmod 600 "$log" "$raw"

tf="$repo/hosts/terraform/home/k8s"
ap() { (cd "$repo/hosts/ansible" && ansible-playbook -i "$INVENTORY" "$@"); }
tofu_k8s() {
  # shellcheck source=/dev/null
  (set -a; . "$TOFU_ENV"; set +a; tofu -chdir="$tf" "$@")
}

# The recap's "changed=" counts, summed over every host, from the last playbook run in $raw.
changed_total() {
  awk '/PLAY RECAP/{n=0} /changed=/{for(i=1;i<=NF;i++) if($i ~ /^changed=/){split($i,a,"="); n+=a[2]}} END{print n+0}' "$raw"
}

wait_apps() {
  local timeout=${APPS_TIMEOUT:-1200} start bad
  start=$(date +%s)
  while :; do
    bad=$(kubectl -n argocd get applications.argoproj.io \
      -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}' \
      | awk '$2 != "Synced" || $3 != "Healthy"')
    if [ -z "$bad" ] && [ "$(kubectl -n argocd get applications.argoproj.io --no-headers | wc -l)" -gt 1 ]; then
      return 0
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      echo "not Synced and Healthy after ${timeout}s:"; echo "$bad"
      return 1
    fi
    sleep 15
  done
}

checks() {
  local notready pods
  notready=$(kubectl get nodes --no-headers | awk '$2 != "Ready"')
  [ -z "$notready" ] || { echo "nodes not Ready: $notready"; return 1; }
  pods=$(kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed"')
  [ -z "$pods" ] || { echo "pods not Running or Completed:"; echo "$pods"; return 1; }
  wait_apps
  # A second run of the cluster playbook must change nothing.
  ap "$repo/hosts/ansible/playbooks/k8s.yml" >> "$raw" 2>&1
  [ "$(changed_total)" = 0 ] || { echo "second k8s.yml run changed $(changed_total) things"; return 1; }
  # And OpenTofu must see no drift (exit 0 = no changes, 2 = changes).
  tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE" >> "$raw" 2>&1
  tofu_k8s plan -detailed-exitcode -input=false -var-file="$TFVARS" >> "$raw" 2>&1
}

run_stage() {
  case $1 in
    teardown)
      tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE"
      tofu_k8s destroy -auto-approve -input=false -var-file="$TFVARS" ;;
    vms)
      [ -z "${PRE_VMS_HOOK:-}" ] || bash -c "$PRE_VMS_HOOK"
      tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE"
      tofu_k8s apply -auto-approve -input=false -var-file="$TFVARS" ;;
    cluster) ap playbooks/k8s.yml ;;
    # The data disks only: Argo CD installs the provisioner and StorageClass (move-local-path-to-argo-cd.md).
    storage) ap playbooks/k8s-storage.yml --tags disk ;;
    gateway) ap playbooks/k8s-gateway.yml ;;
    gitops) ap playbooks/k8s-gitops.yml --tags install,source ;;
    apps) wait_apps ;;
    certs) ap playbooks/k8s-certs.yml ;;
    identity) ap playbooks/k8s-identity.yml ;;
    ui) ap playbooks/k8s-gitops.yml --tags ui,sso ;;
    backup)
      # Backup timers write to the env's restic repository; a dev run must never reach prod's.
      [ "$ENV_NAME" = prod ] || { echo "backup timers run on prod only"; return 1; }
      ap playbooks/k8s-backup.yml ;;
    restore)
      if [ -z "${RESTORE_HOOK:-}" ]; then echo "no RESTORE_HOOK set: restore skipped"; return 0; fi
      bash -c "$RESTORE_HOOK" ;;
    checks) checks ;;
    *) echo "unknown stage: $1"; return 1 ;;
  esac
}

stages=${STAGES:-$default_stages}
[ -z "$only" ] || stages=${only//,/ }
if $teardown && [ -z "$only" ]; then stages="teardown $stages"; fi

echo "rebuild: env $ENV_NAME, stages: $stages, log $log"
for s in $stages; do
  t0=$(date +%s)
  echo "$(date -u +%FT%TZ) $s start" | tee -a "$log"
  echo "===== $s" >> "$raw"
  # A subshell outside any `if`, so `set -e` still stops the stage at its first failed command.
  set +e
  (set -e; run_stage "$s") >> "$raw" 2>&1
  rc=$?
  set -e
  echo "$(date -u +%FT%TZ) $s end rc=$rc $(( $(date +%s) - t0 ))s" | tee -a "$log"
  if [ "$rc" -ne 0 ]; then
    echo "rebuild: stage $s failed; last lines of $raw:" >&2
    tail -n 20 "$raw" >&2
    exit "$rc"
  fi
done
echo "rebuild: all stages passed" | tee -a "$log"
