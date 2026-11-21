#!/usr/bin/env bash
# Rebuild one cluster's Kubernetes layer from this repository in one command: node VMs, the
# cluster, Argo CD and its apps, then checks. Proxmox, OPNsense, DNS and the backup target stay
# as they are (the owner's card, 2026-11-09 23:21 UTC). It stops at the first stage that fails.
#
# Usage: hosts/rebuild-k8s.sh <env-dir> [--teardown] [--only <stage>[,<stage>...]]
#        hosts/rebuild-k8s.sh <env-dir> --fit   (dev only: would the memory preflight pass now? read-only, no log)
#
# <env-dir> is a private folder on the controller (mode 0700), outside the repository. It holds
# rebuild.env (mode 0600), which sets:
#   ENV_NAME      dev or prod
#   VM_ID_MIN     lowest VM ID this env may touch (dev: 250)
#   VM_ID_MAX     highest VM ID this env may touch (dev: 257; 258 is the agent box, 259 was the rehearsal container)
#   TFVARS        the k8s run folder's tfvars for this env
#   TFSTATE       its OpenTofu state file
#   TOFU_ENV      a file that exports PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (and _INSECURE)
#   INVENTORY     the Ansible inventory for this env
#   STAGES        optional: the stages to run, in order (default below)
#   PRE_VMS_HOOK  optional: a command run before the VMs are made (Proxmox /vms ACLs, R4 step 0)
#   TEARDOWN_HOOK  optional: a command the `teardown` stage runs once the destroy has passed (the box's dev wrapper
#                 sets dev-secrets.sh remove, which deletes dev's SOPS file of the apps' secrets while the state holds 0 VMs)
#   TEARDOWN_TARGET  optional: one OpenTofu resource address (no instance key) the `teardown` stage destroys instead of the whole
#                 state. The box's prod wrapper sets proxmox_virtual_environment_vm.node, so a prod teardown destroys the node VMs and
#                 keeps the image and the template they clone from (which prod's state owns). Unset: everything in the state.
#   RESTORE_HOOK  the restore command for stage `restore`; required on dev, where it restores a
#                 read-only copy of prod's newest volume snapshot (hosts/rebuild.env.example)
#   RESTORE_CHECK_HOOK  the command the `checks` stage runs to prove the restore; required with
#                 RESTORE_HOOK
#   PREFLIGHT_KEEP_DESKTOP  optional, dev only: true leaves the owner's desktop VM running when memory is short (the box's
#                 timer run sets it); the preflight then judges without it.
#   PREFLIGHT_MIN_FREE_MIB  optional, dev only: the least free memory (MiB) the Proxmox node must have before the VMs are made
#                 (default: the dev VMs' memory below, summed over the nodes the tfvars declare, plus a 512 MiB margin)
#   APPS_TIMEOUT  optional: seconds to wait for every Argo CD app to be Synced and Healthy (1200)
#   APPS_DEFER    optional: Argo CD apps (space-separated names) the `apps` wait leaves out; `checks` still waits for every app.
#                 The box's prod wrapper sets "gateway jellyfin": on prod the Gateway's HTTPS listener and Jellyfin's lab-CA
#                 Certificate need what the `certs` stage makes (the Gateway's certificate Secret, ClusterIssuer lab-ca),
#                 which runs after `apps`, so those two cannot be Healthy until then (prod run 6, 2026-11-21).
#   OPENBAO_ADDR  optional: the secrets store, https://<name or address> with no path (proposed
#                 D-0038). Set: stage `openbao` registers the cluster's new service-account key with
#                 it. Unset: that stage is skipped.
#   OPENBAO_CACERT, OPENBAO_ROLE_ID_FILE, OPENBAO_SECRET_ID_FILE  with OPENBAO_ADDR: the store's
#                 certificate and the AppRole rebuild's two ID files on the controller
#   OPENBAO_SEAL_KEY_FILE  optional: the 32-byte static seal key of the secrets store inside the
#                 cluster (D-0058 rule 3). Set: stage `openbao-seal` puts it on the node the inventory's
#                 k8s_gitops_source_openbao_seal_node names, before Argo CD makes the store. Unset: that
#                 stage is skipped. On prod it is a secrets step, the owner's tap at the act. On dev it also
#                 turns on the measurement of the box's path through the Gateway (MEASURE-1): the root
#                 Application gets openbaoMeasure, and stage `openbao-measure` runs after `dev-ca`.
#   OPENBAO_ADMIN_ROLE_ID_FILE, OPENBAO_ADMIN_SECRET_ID_FILE  with OPENBAO_SEAL_KEY_FILE, dev only: the box's
#                 admin AppRole IDs on the controller. Stage `openbao-handover` hands the store's admin login
#                 over to them once (D-0038 rule 6), after `openbao-measure`.
#
# No kubeconfig leaves the cluster: every kubectl call runs on the first control-plane node through
# Ansible, with that node's /etc/kubernetes/admin.conf (kc below). A KUBECONFIG in rebuild.env is
# ignored.
#
# The hooks run in bash with REPO (this repository) and INVENTORY exported.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
# gateway runs after apps: with k8s_gateway_by_argocd true, Argo CD makes the Gateway, and the
# playbook's "programmed" wait and smoke test then check it. restore runs after storage made the data
# disk and before gitops: once Argo CD reads the repo it syncs every app, and local-path then finds
# each volume's folder already there (TASK-0240, agent pick 205). openbao runs before apps, whose
# ExternalSecrets wait needs External Secrets to sign in at the store with the new cluster's key.
# openbao-seal runs before gitops: the store's pod in the cluster waits for its seal key from the start.
default_stages="vms cluster storage openbao-seal restore gitops secrets openbao apps gateway certs identity ui checks"

die() { echo "rebuild: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: $0 <env-dir> [--teardown] [--only <stage>[,<stage>...]] | --fit"
env_dir=$1; shift
teardown=false; only=""; fit=false
while [ $# -gt 0 ]; do
  case $1 in
    --teardown) teardown=true ;;
    --only) shift; only=${1:-} ;;
    --fit) fit=true ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[ -f "$env_dir/rebuild.env" ] || die "$env_dir/rebuild.env is missing"
[ "$(stat -c %a "$env_dir" 2>/dev/null || stat -f %Lp "$env_dir")" = 700 ] || die "$env_dir must be mode 0700"
# shellcheck source=/dev/null
. "$env_dir/rebuild.env"
for v in ENV_NAME VM_ID_MIN VM_ID_MAX TFVARS TFSTATE TOFU_ENV INVENTORY; do
  [ -n "${!v:-}" ] || die "$v is not set in rebuild.env"
done
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

# Dev only: the memory (MiB) each dev node gets by role, in place of its memory_mb in the tfvars (the k8s stack's
# memory_mb_by_role). Dev is a rebuild test beside the always-on guests, so it is sized to what the host has free beside
# them: 11296 MiB at the run of 2026-11-18 13:14 UTC and 11237 MiB at 19:19 UTC with VM 300 stopped (run
# 20261118T191933Z, refused at 10240 + 1024 = 11264). Control plane 4096 again since 2026-11-19 (3584 from 2026-11-18
# 14:27 UTC): with #693's kubelet reservations (384 + 256 MiB held back, eviction below 384 MiB available) 3584 left the
# control plane at 103 to 110% of its allocatable memory, 173 MiB free and 735 available of 3405, and Ansible's sudo on it
# timed out (12 s) in identity-keycloak (run 20261119T091356Z, `fail:` and `node psi` lines). At 4096 dev's read 2403 to
# 2839 MiB in run 20261118T131441Z, and 3072 starved the API server (run 20261118T061140Z).
# Worker 8192 since 2026-11-19 (6400 from 2026-11-18 14:27 UTC): at 6400, with the control plane at 4096 and
# the kubelet reservations, run 20261119T095027Z lost the worker in identity-keycloak: it read 4725 MiB used, 141 free and
# 1446 available of 6171 at 10:14:41 UTC, then answered no ssh (banner timeout) from 10:16 UTC while Proxmox counted 6108
# to 6119 of 6400 MiB, and the realm import never finished (1200 s). At 7168 run 20261117T053037Z passed with the worker
# at 4255 MiB; 8192 is the box's own tfvars size. Before that: at 6144 the worker never passed
# identity-keycloak (runs 20261117T043328Z and 20261118T131441Z) while the realm import ran with the operator's default
# memory, request 1700Mi and limit 2Gi, beside Keycloak's own pod; dev now caps the import at DEV_REALM_IMPORT_MEMORY
# below, 1 GiB less, and the worker then kept 256 MiB more than the size that failed (6400). The sum, 12288, plus the 512 MiB
# margin is 12800; the node read 15409 MiB available with dev down (`rebuild fit`, 2026-11-19 09:38 UTC). c1 (prod) keeps the sizes in its own tfvars.
DEV_MEMORY_MB_CONTROL_PLANE=4096
DEV_MEMORY_MB_WORKER=8192
# The preflight's margin is 512 MiB: 4096 + 8192 + 512 = 12800. It was 1024 (11008) until 2026-11-19; the fit check at
# 05:37 UTC that day read an estimate of 10562 MiB with VM 300 counted as freed, 446 short of 11008, with the agent
# box already holding only 620 MiB of cache (its drop-cache timer) and 1195 of the node's 8191 MiB swap in use. The
# margin guards the node, not dev's VMs, whose sizes are fixed above; the node keeps its swap beside it.
# Dev only: how long identity-keycloak waits for the realm import (seconds; the role's default is 600). At 6144 MiB the
# worker's import timed out at 600 s on 2026-11-17 at 04:33 UTC; at 7168 MiB the whole stage took 176 s (run
# 20261117T053037Z). 1200 gives the smaller worker twice the wait that ran out; if it still times out, the node-top
# lines say whether memory or CPU ran short.
DEV_REALM_IMPORT_TIMEOUT_S=1200
# Dev only: the realm import job's memory, request and limit (the role's k8s_identity_realm_import_memory). Unset,
# the Keycloak operator 26.8.2 gives the job request 1700Mi and limit 2Gi (operator application.properties lines 15
# and 16, applied by KeycloakRealmImportJobDependentResource line 173), and Keycloak's JVM takes half the limit as its
# first heap (kc.sh line 100). 1Gi bounds the import's JVM to 70% of 1 GiB, so the import fails inside its own limit
# rather than pressing on the whole worker.
DEV_REALM_IMPORT_MEMORY=1Gi
# Dev only: kubelet memory reservations and eviction on every dev node (role k8s_node, k8s_node_kubelet_*). The dev worker was
# lost under Keycloak in runs 20261118T131441Z (13:41 UTC) and 20261119T055343Z (06:19 UTC): the worker read 4007 and 4177 MiB
# (68%), then stopped answering with pods Terminating or Pending. No kubelet reservation or eviction threshold existed under
# hosts/, so pods and page cache could take the whole worker VM (no swap, floating = 0) and starve the kubelet and containerd.
# With these the kubelet holds back 384 + 256 MiB for the system and itself, and evicts pods when less than 384 MiB is
# available, so a pod is killed before the node is lost. c1 (prod) sets none and keeps its kubelet as it is.
# Unproven: the box's raw logs were not read for the 06:19 run, so memory exhaustion is the cause the evidence fits, not one seen.
DEV_KUBELET_SYSTEM_RESERVED_MEMORY=384Mi
DEV_KUBELET_KUBE_RESERVED_MEMORY=256Mi
DEV_KUBELET_EVICTION_HARD_MEMORY=384Mi
kubelet_vars=()
if [ "$ENV_NAME" = dev ]; then
  kubelet_vars=(-e "k8s_node_kubelet_system_reserved_memory=$DEV_KUBELET_SYSTEM_RESERVED_MEMORY"
    -e "k8s_node_kubelet_kube_reserved_memory=$DEV_KUBELET_KUBE_RESERVED_MEMORY"
    -e "k8s_node_kubelet_eviction_hard_memory=$DEV_KUBELET_EVICTION_HARD_MEMORY")
fi
tofu_vars=(-var-file="$TFVARS")
if [ "$ENV_NAME" = dev ]; then
  tofu_vars+=(-var "memory_mb_by_role={\"control-plane\" = $DEV_MEMORY_MB_CONTROL_PLANE, \"worker\" = $DEV_MEMORY_MB_WORKER}")
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
$fit || mkdir -p "$env_dir/logs"
log="$env_dir/logs/rebuild-$stamp.log"
raw="$env_dir/logs/rebuild-$stamp.raw"
# --fit writes no run log: `rebuild log` and rebuild-prod's dev-first check read these logs, and a fit check is no run.
if $fit; then log=/dev/null raw=/dev/null; else : > "$log"; : > "$raw"; chmod 600 "$log" "$raw"; fi

tf="$repo/hosts/terraform/home/k8s"
ap() { (cd "$repo/hosts/ansible" && ansible-playbook -i "$INVENTORY" "$@"); }
tofu_k8s() {
  # shellcheck source=/dev/null
  (set -a; . "$TOFU_ENV"; set +a; tofu -chdir="$tf" "$@")
}

# kubectl on the first control-plane node, through Ansible, so no admin kubeconfig is copied off
# the node. Prints the command's stdout, sends its stderr to stderr, and returns its exit code.
# The arguments are split on spaces on the node, so pass no argument that holds a space or quote.
kc() {
  local json rc=0
  # ansible.posix.json (pinned in hosts/ansible/requirements.yml) prints the run as one JSON document.
  json=$(cd "$repo/hosts/ansible" && ANSIBLE_LOAD_CALLBACK_PLUGINS=1 ANSIBLE_STDOUT_CALLBACK=ansible.posix.json \
    ansible 'k8s_control_plane[0]' -i "$INVENTORY" -b -m ansible.builtin.command \
    -a "kubectl --kubeconfig /etc/kubernetes/admin.conf $*") || rc=$?
  printf '%s' "$json" | python3 -I -c '
import json, sys
try:
    res = list(json.load(sys.stdin)["plays"][0]["tasks"][0]["hosts"].values())[0]
except Exception as e:
    print("kc: no result from Ansible: %s" % e, file=sys.stderr); sys.exit(1)
if res.get("stdout"): print(res["stdout"])
err = res.get("stderr") or ("" if "rc" in res else res.get("msg", ""))
if err: print(err, file=sys.stderr)
sys.exit(res.get("rc", 1))
' || rc=$?
  return "$rc"
}

# The secrets store's CA, for the box's calls that sign in (stage app-secrets' put-apps and compare, and the box's other
# dev secrets-store calls until the next rebuild): ca.crt of Secret openbao/openbao-tls, a public certificate, read
# from this run's store. Each store makes its own CA (apps/openbao-store templates/tls.yaml), so a copy from an earlier
# run would fail TLS. The same read and checks as the box's openbao-prod ca: only the ca.crt field (the same Secret
# holds the server's tls.key, which is never read), written only if it is exactly one PEM certificate.
# kc's arguments reach Ansible's command module as one string, which it splits as a shell would (shlex), so the inner
# single quotes keep the backslash before the key's dot: kubectl then reads key ca.crt, not ca then crt.
store_ca() {
  local pem
  pem=$(kc -n openbao get secret openbao-tls -o "'jsonpath={.data.ca\.crt}'" | base64 -d) ||
    { echo "app-secrets: could not read ca.crt of Secret openbao/openbao-tls; nothing written"; return 1; }
  if [ "$(printf '%s\n' "$pem" | grep -c -- '-----BEGIN ')" -ne 1 ] ||
     [ "$(printf '%s\n' "$pem" | grep -c -- '-----BEGIN CERTIFICATE-----')" -ne 1 ] ||
     ! printf '%s\n' "$pem" | openssl x509 -noout 2>/dev/null; then
    echo "app-secrets: ca.crt of Secret openbao/openbao-tls is not one PEM certificate; nothing written"; return 1
  fi
  printf '%s\n' "$pem" > "$1.part" && mv -- "$1.part" "$1"
  echo "app-secrets: the store's CA written to $1 ($(printf '%s\n' "$pem" | openssl x509 -noout -subject -enddate | tr '\n' ' '))"
}

# The recap's "changed=" counts, summed over every host, from the last playbook run in $raw.
changed_total() {
  awk '/PLAY RECAP/{n=0} /changed=/{for(i=1;i<=NF;i++) if($i ~ /^changed=/){split($i,a,"="); n+=a[2]}} END{print n+0}' "$raw"
}

# wait_apps [<apps to leave out>]: only the `apps` stage passes APPS_DEFER; `checks` waits for every app.
wait_apps() {
  local defer=${1:-} timeout=${APPS_TIMEOUT:-1200} start apps bad
  start=$(date +%s)
  while :; do
    apps=$(kc -n argocd get applications.argoproj.io --no-headers \
      -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status)
    bad=$(printf '%s\n' "$apps" | awk -v defer=" $defer " 'NF && ($2 != "Synced" || $3 != "Healthy") && index(defer, " " $1 " ") == 0')
    if [ -z "$bad" ] && [ "$(printf '%s\n' "$apps" | awk 'NF' | wc -l)" -gt 1 ]; then
      return 0
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      echo "not Synced and Healthy after ${timeout}s:"; echo "$bad"
      return 1
    fi
    sleep 15
  done
}

# The vms stage returns when the guests exist, not when sshd answers: a fresh VM is still booting
# (seen 2026-11-13, cluster failed in 0s on "Connection refused"). Waits until every host takes an ssh
# login (every node, as k8s.yml targets), stopping at the condition or at SSH_TIMEOUT (default 300 s).
wait_ssh() {
  (cd "$repo/hosts/ansible" && ansible k8s_nodes -i "$INVENTORY" -m ansible.builtin.wait_for_connection \
    -a "timeout=${SSH_TIMEOUT:-300}")
}

# Every ExternalSecret re-read now and Ready, then the pods that mount their Secrets Ready. ESO retries
# a failed read with a growing backoff, so without the nudge a pod can wait minutes on a Secret whose
# source was seeded a moment ago. Each wait stops at a condition or at its timeout, never on a sleep.
wait_secrets() {
  local timeout=${SECRETS_TIMEOUT:-300} notready
  kc annotate --request-timeout=60s externalsecrets.external-secrets.io -A --all --overwrite "force-sync=$(date -u +%Y%m%dT%H%M%SZ)" >/dev/null
  if ! kc wait externalsecrets.external-secrets.io -A --all --for=condition=Ready "--timeout=${timeout}s" >/dev/null; then
    notready=$(kc get --request-timeout=60s externalsecrets.external-secrets.io -A --no-headers \
      -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status | awk '$3 != "True"')
    echo "ExternalSecrets not Ready after ${timeout}s:"; echo "$notready"
    return 1
  fi
  kc -n alerts rollout status deployment/ntfy "--timeout=${timeout}s" >/dev/null || { echo "ntfy not Ready after ${timeout}s"; return 1; }
  kc -n monitoring wait pod/alertmanager-kube-prometheus-stack-alertmanager-0 --for=condition=Ready "--timeout=${timeout}s" >/dev/null \
    || { echo "alertmanager-0 not Ready after ${timeout}s"; return 1; }
}

# Dev, at the end of the gateway stage and in a failed run's capture: every LoadBalancer Service, its address, the L2
# announcement policy meant to announce it and the node holding its lease, by the role's own report
# (hosts/ansible/roles/k8s_control_plane/files/l2-report.py, which `openbao-prod l2-policy` runs on prod). D-0062
# narrowed the general policy to Services without the label central-hub/l2-policy, so a Service with an address and no
# lease holder is one no policy announces: it fails. Read-only.
l2_report() {
  local d rc=0
  d=$(mktemp -d)
  if kc get svc -A -o json > "$d/svc" && kc -n kube-system get leases -o json > "$d/leases"; then
    python3 -I "$repo/hosts/ansible/roles/k8s_control_plane/files/l2-report.py" "$d/svc" "$d/leases" || rc=$?
  else
    echo "l2: FAIL: the Services or the leases could not be read"; rc=1
  fi
  rm -rf "$d"
  return "$rc"
}

checks() {
  local notready pods
  notready=$(kc get nodes --no-headers | awk '$2 != "Ready"')
  [ -z "$notready" ] || { echo "nodes not Ready: $notready"; return 1; }
  pods=$(kc get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed"')
  [ -z "$pods" ] || { echo "pods not Running or Completed:"; echo "$pods"; return 1; }
  wait_apps
  # A second run of the cluster playbook must change nothing.
  ap "$repo/hosts/ansible/playbooks/k8s.yml" "${kubelet_vars[@]}" >> "$raw" 2>&1
  [ "$(changed_total)" = 0 ] || { echo "second k8s.yml run changed $(changed_total) things"; return 1; }
  # And OpenTofu must see no drift (exit 0 = no changes, 2 = changes).
  tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE" >> "$raw" 2>&1
  tofu_k8s plan -detailed-exitcode -input=false "${tofu_vars[@]}" >> "$raw" 2>&1
  # The restored data is what the apps use (TASK-0240).
  if [ -n "${RESTORE_HOOK:-}" ]; then
    [ -n "${RESTORE_CHECK_HOOK:-}" ] || { echo "RESTORE_HOOK is set but RESTORE_CHECK_HOOK is not: nothing proves the restore"; return 1; }
    hook "$RESTORE_CHECK_HOOK"
  fi
}

# A hook from rebuild.env, with the repository and the inventory it needs.
hook() { REPO=$repo INVENTORY=$INVENTORY bash -c "$1"; }

# Dev only, before the VMs, for a fresh build or after a teardown (a re-run on existing VMs is skipped, and the
# log says which branch ran): the Proxmox node must have enough free memory for the dev VMs beside the guests
# already running (an agent pick from the measured RAM figures, the capacity plan v2.4 that Councils A, B and C passed on 2026-11-14). It reads the node's memory with the same token
# the VMs use and refuses below PREFLIGHT_MIN_FREE_MIB (default: the dev VMs' memory by role, summed over the nodes
# the tfvars declare, plus a 512 MiB margin; 4096 + 8192 + 512 = 12800 for one control plane and one worker). If the
# read fails, it refuses too: a number nobody saw is not a pass. Prints sizes in MiB only, never the token.
# curl's error text in one short line, with the Proxmox token's secret part replaced by ***. Both preflight calls
# use it, so neither can print the token.
preflight_clean() {
  local secret text
  # shellcheck source=/dev/null
  secret=$(set -a; . "$TOFU_ENV"; printf '%s' "${PROXMOX_VE_API_TOKEN##*=}")
  # Redact first and cut after, so a secret that crosses the cut can't leave a partial prefix.
  text=$(printf '%s' "$1" | tr -d '\n')
  [ -z "$secret" ] || text=${text//"$secret"/***}
  printf '%s' "${text:0:200}"
}

# The guests the token can see (VM ID, type, status, maxmem and mem in MiB, name), one line each, so a refusal
# shows what is using the node. Read-only and never fatal: a read that fails prints one line saying so. The
# token only lists guests it holds audit rights on.
preflight_guests() {
  local out
  # shellcheck source=/dev/null
  out=$( (set -a; . "$TOFU_ENV"; set +a
    insecure=(); case "${PROXMOX_VE_INSECURE:-}" in true|1) insecure=(-k) ;; esac
    printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
      curl -sS --fail --max-time 30 "${insecure[@]}" -K - "${PROXMOX_VE_ENDPOINT%/}/api2/json/cluster/resources?type=vm") 2>&1) \
    || { echo "preflight: guest list could not be read: $(preflight_clean "$out")"; return 1; }
  printf '%s' "$out" | python3 -c 'import json,sys
rows = sorted(json.load(sys.stdin)["data"], key=lambda r: r.get("vmid", 0))
print("preflight: guest list from /cluster/resources?type=vm, %d guests visible to the token" % len(rows))
print("preflight: guest note: only guests the token can see are listed; VM 258 is NoAccess for it (agent-access.sh, NO_ACCESS), so the memory these lines add up to undercounts")
for r in rows:
    print("preflight: guest vmid=%s type=%s status=%s maxmem=%s MiB mem=%s MiB name=%s pool=%s" % (
        r.get("vmid"), r.get("type"), r.get("status"), r.get("maxmem", 0) // 1048576, r.get("mem", 0) // 1048576,
        "".join(c for c in str(r.get("name", "")) if c.isalnum() or c in "-_."),
        "".join(c for c in str(r.get("pool", "")) if c.isalnum() or c in "-_.")))' \
    || { echo "preflight: guest list had an unexpected shape"; return 1; }
}

# One call to the Proxmox API with the same token (header on stdin, never in curl's arguments). The path starts
# after /api2/json. Used for the node's memory read and the CI runner's stop and start.
px_api() { # method path [form data]
  local method=$1 path=$2 data=${3:-}
  # shellcheck source=/dev/null
  (set -a; . "$TOFU_ENV"; set +a
    insecure=(); case "${PROXMOX_VE_INSECURE:-}" in true|1) insecure=(-k) ;; esac
    printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
      curl -sS --fail --max-time 30 "${insecure[@]}" -K - -X "$method" ${data:+--data "$data"} "${PROXMOX_VE_ENDPOINT%/}/api2/json/$path") 2>&1
}

# The memory the declared dev nodes need, in MiB: each node block in the tfvars that has a vm_id is counted by its
# role, at the dev size for that role. A node with no role, or another role, fails: a sum nobody can check is not a
# minimum.
preflight_declared_mib() {
  python3 -c 'import re, sys
sizes = {"control-plane": int(sys.argv[2]), "worker": int(sys.argv[3])}
total = 0
for block in re.findall(r"\{([^{}]*)\}", open(sys.argv[1]).read()):
    if not re.search(r"(^|[^_\w])vm_id\s*=\s*\d+", block):
        continue
    role = re.search(r"(^|[^_\w])role\s*=\s*\"([^\"]*)\"", block)
    if not role or role.group(2) not in sizes:
        sys.exit("preflight: a declared node has no role control-plane or worker, so its memory is unknown")
    total += sizes[role.group(2)]
print(total)' "$TFVARS" "$DEV_MEMORY_MB_CONTROL_PLANE" "$DEV_MEMORY_MB_WORKER"
}

# The node's whole memory picture, one line, read-only and never fatal: total, used, available, KSM's shared
# pages and swap, all from /nodes/<node>/status (Proxmox reports ksm.shared in bytes). The guest list can't show
# the guests the token can't see, so this says what the node as a whole holds.
preflight_node_detail() { # node
  local body
  body=$(px_api GET "nodes/$1/status") || { echo "preflight: node memory detail could not be read"; return 0; }
  printf '%s' "$body" | python3 -c 'import json,sys
d = json.load(sys.stdin)["data"]
m, k, w = d.get("memory") or {}, d.get("ksm") or {}, d.get("swap") or {}
mib = lambda v: "?" if v is None else str(int(v) // 1048576)
print("preflight: node memory total %s used %s available %s MiB; ksm shared %s MiB; swap used %s of %s MiB" % (
    mib(m.get("total")), mib(m.get("used")), mib(m.get("available")), mib(k.get("shared")), mib(w.get("used")), mib(w.get("total"))))' \
    || echo "preflight: node memory detail had an unexpected shape"
}

# The node's free memory in MiB and the field it came from ("MiB field"), or a failure that says why.
preflight_read_free() { # node
  local body
  body=$(px_api GET "nodes/$1/status") \
    || { body=$(preflight_clean "$body")
         echo "preflight: the node's memory could not be read: $body"; return 1; }
  # memory.available (the kernel's MemAvailable) exists from PVE 9; older versions have total - used.
  printf '%s' "$body" | python3 -c 'import json,sys
m = json.load(sys.stdin)["data"]["memory"]
if m.get("available") is not None:
    print(m["available"] // 1048576, "available")
else:
    print((m["total"] - m["used"]) // 1048576, "total-used")' \
    || { echo "preflight: the node's memory answer had no memory figures"; return 1; }
}

# Dev only, and only when the preflight is short: stop VM 300 (the CI runner, a guest the token holds VM.PowerMgmt
# on, pool ci) so its memory counts, and start it again when the run ends, pass or fail (runner_restart, an EXIT
# trap). It touches no other guest. The marker file is written before the stop request, so a run that dies
# without its trap still leaves the next run a reason to start the runner.
CI_RUNNER_VMID=300
DESKTOP_VMID=400   # the one desktop VM the token may stop (agent-access.sh, DESKTOP_POWER_VMID)
OPNSENSE_TEST_VMID=257
LAB_TEST_VMID=256   # the lab test copy (hosts/terraform/home/lab-test), built only while dev is down
runner_mark() { printf '%s' "$env_dir/ci-runner-stopped"; }
preflight_stop_runner() { # node
  local node=$1 i st out
  echo "runner stop: short on memory and VM $CI_RUNNER_VMID is running, asking it to shut down (VM.PowerMgmt, nothing else is touched)"
  # The marker holds this run's stamp, so the end of the run knows it was this run that stopped VM 300.
  printf '%s\n' "$stamp" > "$(runner_mark)"
  out=$(px_api POST "nodes/$node/qemu/$CI_RUNNER_VMID/status/shutdown" "timeout=60") \
    || { echo "runner stop: the shutdown request failed: $(preflight_clean "$out")"; rm -f "$(runner_mark)"; return 1; }
  for i in $(seq 1 24); do
    st=$(px_api GET "nodes/$node/qemu/$CI_RUNNER_VMID/status/current" | python3 -c 'import json,sys
print(json.load(sys.stdin)["data"].get("status", ""))' 2>/dev/null) || st=""
    [ "$st" != stopped ] || { echo "runner stop: VM $CI_RUNNER_VMID is stopped after $(( (i - 1) * 5 )) s"; return 0; }
    sleep 5
  done
  echo "runner stop: VM $CI_RUNNER_VMID did not stop within 120 s"; return 1
}

# Dev only, and only when the preflight is short: stop the owner's desktop VM (DESKTOP_VMID, an unused guest must never
# block this run; the owner's words of 2026-11-17 23:58 UTC) when it is running (matched by its ID; the token cannot see pools). The token holds VM.Audit
# and VM.PowerMgmt on that one VM and nothing else (agent-access.sh, role AgentDesktopPower). It is a shutdown,
# then a forced stop after 60 s, and nothing starts it again: the owner starts it when the desktop is wanted. It does not
# check whether anyone is signed in (the token can't read the guest), so it stops a desktop in use too; the runbook says so.
preflight_stop_desktops() { # node vmid...
  local node=$1 id i st out
  shift
  for id in "$@"; do
    echo "desktop stop: short on memory and VM $id (the desktop) is running, asking it to shut down (VM.PowerMgmt, nothing else is touched)"
    out=$(px_api POST "nodes/$node/qemu/$id/status/shutdown" "timeout=60&forceStop=1") \
      || { echo "desktop stop: the shutdown request for VM $id failed: $(preflight_clean "$out")"; return 1; }
    st=""
    for i in $(seq 1 24); do
      st=$(px_api GET "nodes/$node/qemu/$id/status/current" | python3 -c 'import json,sys
print(json.load(sys.stdin)["data"].get("status", ""))' 2>/dev/null) || st=""
      [ "$st" != stopped ] || { echo "desktop stop: VM $id is stopped after $(( (i - 1) * 5 )) s; it stays stopped until the owner starts it"; break; }
      sleep 5
    done
    [ "$st" = stopped ] || { echo "desktop stop: VM $id did not stop within 120 s"; return 1; }
  done
}

# The EXIT trap: start the CI runner again if this run (or an earlier one that died) stopped it. Never fatal. The
# runner is the notebook's CI runner (docs/runbooks/set-up-the-ci-runner.md), so it starts only when the node has
# its memory (VM 300's maxmem) plus 2048 MiB free again, so the start can't push the node back into the shortage that
# stopped it. If not, it stays stopped, the marker stays, and the log says so: notebook checks queue meanwhile.
# A dev cluster that stays up leaves too little free memory, so the runner starts on the next run's start only after a
# teardown has freed the dev VMs.
runner_restart() {
  local node out cur maxmem free needs margin=2048
  [ -f "$(runner_mark)" ] || return 0
  node=$(sed -n 's/^[[:space:]]*proxmox_node_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS" | head -1)
  cur=$(px_api GET "nodes/$node/qemu/$CI_RUNNER_VMID/status/current") \
    && maxmem=$(printf '%s' "$cur" | python3 -c 'import json,sys
print(json.load(sys.stdin)["data"]["maxmem"] // 1048576)' 2>/dev/null) || maxmem=""
  free=$(preflight_read_free "$node" 2>/dev/null) && free=${free% *} || free=""
  if [ -z "$maxmem" ] || [ -z "$free" ]; then
    echo "runner left stopped: could not read the memory figures (VM $CI_RUNNER_VMID stays stopped, notebook checks queue)" | tee -a "$log"
    return 0
  fi
  needs=$(( maxmem + margin ))
  if [ "$free" -lt "$needs" ]; then
    echo "runner left stopped: not enough memory (free $free MiB, needs $needs MiB), notebook checks queue until it is started" | tee -a "$log"
    return 0
  fi
  if out=$(px_api POST "nodes/$node/qemu/$CI_RUNNER_VMID/status/start"); then
    echo "runner restart: VM $CI_RUNNER_VMID started again (free $free MiB, needs $needs MiB)" | tee -a "$log"
    rm -f "$(runner_mark)"
  else
    # The marker stays, so the next dev run tries the start again.
    echo "runner restart: VM $CI_RUNNER_VMID start failed, marker kept: $(preflight_clean "$out")" | tee -a "$log"
  fi
  return 0
}

# The node's storages the token can see (name and type only), one line each, so the log shows whether the host
# uses ZFS (whose ARC the node's memory.available may not count). Read-only and never fatal.
preflight_storage() { # node
  local out
  out=$(px_api GET "nodes/$1/storage") \
    || { echo "preflight: storage list could not be read: $(preflight_clean "$out")"; return 1; }
  printf '%s' "$out" | python3 -c 'import json,sys
rows = sorted(json.load(sys.stdin)["data"], key=lambda r: str(r.get("storage", "")))
print("preflight: storage list from /nodes/<node>/storage, %d storages visible to the token" % len(rows))
for r in rows:
    print("preflight: storage name=%s type=%s" % (
        "".join(c for c in str(r.get("storage", "")) if c.isalnum() or c in "-_."),
        "".join(c for c in str(r.get("type", "")) if c.isalnum() or c in "-_.")))' \
    || { echo "preflight: storage list had an unexpected shape"; return 1; }
}

preflight_memory() {
  local min node free field guests desktops needs margin=512 add
  local existing declared
  # A re-run on VMs the state already holds allocates no new VMs, and their memory is already taken, so the
  # node's free memory says nothing about it (measured on the box, 2026-11-14: 3547 MiB free with dev up).
  # Only a fresh build, or a run after a teardown, is checked. An unreadable state file counts as no VMs.
  existing=$(python3 -c 'import json,sys
try:
    st = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print(0); raise SystemExit
print(sum(len(r.get("instances", [])) for r in st.get("resources", [])
          if r.get("mode") == "managed" and r.get("type") == "proxmox_virtual_environment_vm"))' "$TFSTATE" 2>/dev/null || echo 0)
  # Skipped only when the state holds every VM the tfvars declare; a partial state still has VMs to make.
  declared=$(grep -Eo '(^|[^_[:alnum:]])vm_id[[:space:]]*=[[:space:]]*[0-9]+' "$TFVARS" | grep -Eo '[0-9]+$' | sort -u | wc -l)
  if [ "${declared:-0}" -gt 0 ] && [ "${existing:-0}" -ge "$declared" ]; then
    echo "preflight: branch skipped, all ${declared} declared dev VMs already exist in the state, so a re-run allocates no new VMs"
    return 0
  fi
  echo "preflight: branch checked, the state holds ${existing:-0} of ${declared:-0} declared dev VMs (a fresh build, a partial state or after a teardown)"
  needs=$(preflight_declared_mib 2>&1) || { echo "$needs"; return 1; }
  min=${PREFLIGHT_MIN_FREE_MIB:-$(( needs + margin ))}
  echo "preflight: the declared dev VMs need ${needs} MiB (control plane ${DEV_MEMORY_MB_CONTROL_PLANE}, worker ${DEV_MEMORY_MB_WORKER}); minimum ${min} MiB$([ -n "${PREFLIGHT_MIN_FREE_MIB:-}" ] && echo ', set in rebuild.env' || echo " with the ${margin} MiB margin")"
  node=$(sed -n 's/^[[:space:]]*proxmox_node_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS" | head -1)
  [ -n "$node" ] || { echo "preflight: proxmox_node_name not found in the tfvars"; return 1; }
  free=$(preflight_read_free "$node") || { echo "$free"; return 1; }
  field=${free#* }; free=${free% *}
  echo "preflight: node free memory ${free} MiB (field: ${field}), minimum ${min} MiB"
  preflight_node_detail "$node"
  guests=$(preflight_guests) || true
  printf '%s\n' "$guests"
  # VM 257 is the OPNsense test VM (hosts/terraform/home/opnsense-test), built only while dev is down: a dev
  # build never starts beside it. An unreadable guest list can't show it, and the log says so.
  if grep -q "guest vmid=$OPNSENSE_TEST_VMID " <<<"$guests"; then
    echo "preflight: refused, VM $OPNSENSE_TEST_VMID (the OPNsense test VM) exists; run opnsense-test destroy first"
    return 1
  fi
  # VM 256 is the lab test copy (hosts/terraform/home/lab-test, docs/specs/2026-11-lab-test-copy.md), built only while
  # dev is down, for the same reason.
  if grep -q "guest vmid=$LAB_TEST_VMID " <<<"$guests"; then
    echo "preflight: refused, VM $LAB_TEST_VMID (the lab test copy) exists; run lab-test destroy first"
    return 1
  fi
  grep -q "guest list from" <<<"$guests" || echo "preflight: the guest list was not read, so VM $OPNSENSE_TEST_VMID (the OPNsense test VM) and VM $LAB_TEST_VMID (the lab test copy) could not be checked"
  preflight_storage "$node" || true
  if [ "$free" -lt "$min" ]; then
    # Matched by its ID alone: /cluster/resources leaves out the pool field when the token lacks Pool.Audit on
    # /pool/desktop, which the dev token does (it holds rights on /vms/<DESKTOP_VMID> only), and that ID is the
    # only one the token's VM.PowerMgmt covers.
    desktops=$(sed -n "s/^preflight: guest vmid=\($DESKTOP_VMID\) type=qemu status=running .*/\1/p" <<<"$guests")
    if [ -n "$desktops" ] && ${PREFLIGHT_KEEP_DESKTOP:-false}; then
      # A timer run (the box's rebuild.sh auto) never stops the owner's desktop: it is judged without it.
      echo "preflight: VM $DESKTOP_VMID (the desktop) is running and is left alone (PREFLIGHT_KEEP_DESKTOP: a timer run never stops it)"
    elif [ -n "$desktops" ] && ${PREFLIGHT_DRY:-false}; then
      # A fit check stops nothing: it counts the desktop's maxmem as freed, which the stop frees at most.
      add=$(sed -n "s/^preflight: guest vmid=$DESKTOP_VMID type=qemu status=running maxmem=\([0-9]*\) MiB .*/\1/p" <<<"$guests")
      free=$(( free + ${add:-0} ))
      echo "preflight: fit check: VM $DESKTOP_VMID (the desktop) is running; a run would stop it; its maxmem ${add:-0} MiB counted as freed, estimate ${free} MiB, minimum ${min} MiB"
    elif [ -n "$desktops" ]; then
      # shellcheck disable=SC2086
      preflight_stop_desktops "$node" $desktops || { echo "preflight: refused, free memory ${free} MiB is below ${min} MiB and a desktop VM could not be stopped"; return 1; }
      sleep 5
      free=$(preflight_read_free "$node") || { echo "$free"; return 1; }
      field=${free#* }; free=${free% *}
      echo "preflight: node free memory ${free} MiB (field: ${field}) after the desktop VM stopped, minimum ${min} MiB"
    fi
  fi
  if [ "$free" -lt "$min" ] && grep -q "guest vmid=$CI_RUNNER_VMID type=qemu status=running" <<<"$guests"; then
    # What happens on a short node is the owner's pick (PREFLIGHT_SHORT_NODE, set at the install of the box's
    # checkout). With no valid value there is no default: it refuses BEFORE it stops VM 300.
    case ${PREFLIGHT_SHORT_NODE:-} in
      ephemeral-dev|keep-dev) ;;
      *) echo "preflight: refused, free memory ${free} MiB is below ${min} MiB, VM $CI_RUNNER_VMID was not stopped because the short-node setting is not set (agent_box_short_node). Two values: ephemeral-dev (stops VM $CI_RUNNER_VMID, tears dev down at the end of the run, then starts VM $CI_RUNNER_VMID: dev lasts one run, notebook CI keeps running except during the run) or keep-dev (stops VM $CI_RUNNER_VMID, dev stays up: the notebook's queued jobs fail or are cancelled after 24 hours queued, so if dev stays up for more than a day the daily access-expiry check does not run and its alert e-mail may not go out)"
         return 1 ;;
    esac
    echo "preflight: short-node setting is ${PREFLIGHT_SHORT_NODE}"
    if ${PREFLIGHT_DRY:-false}; then
      add=$(sed -n "s/^preflight: guest vmid=$CI_RUNNER_VMID type=qemu status=running maxmem=\([0-9]*\) MiB .*/\1/p" <<<"$guests")
      free=$(( free + ${add:-0} ))
      echo "preflight: fit check: VM $CI_RUNNER_VMID is running; a run would stop it; its maxmem ${add:-0} MiB counted as freed, estimate ${free} MiB, minimum ${min} MiB"
      [ "$free" -ge "$min" ] || { echo "preflight: refused, estimate ${free} MiB is below ${min} MiB"; return 1; }
      return 0
    fi
    preflight_stop_runner "$node" || { echo "preflight: refused, free memory ${free} MiB is below ${min} MiB and VM $CI_RUNNER_VMID could not be stopped"; return 1; }
    sleep 5
    free=$(preflight_read_free "$node") || { echo "$free"; return 1; }
    field=${free#* }; free=${free% *}
    echo "preflight: node free memory ${free} MiB (field: ${field}) after VM $CI_RUNNER_VMID stopped, minimum ${min} MiB"
  fi
  [ "$free" -ge "$min" ] || { echo "preflight: refused, free memory ${free} MiB is below ${min} MiB"; return 1; }
}

# Dev only, the last stage of a full dev run, before the end-of-run teardown: what an agent read by hand after a run,
# read inside it, so it is in the short log when ephemeral-dev tears dev down. One Job from the suspended panel-check
# CronJob (the dashboard's panels, then the alerts firing), whether Prometheus scrapes namespaces openbao and media, and
# the store's StatefulSet's age (a [5m] rate has no data in a store's first minutes). It changes nothing but that one
# Job. A fresh store has no snapshot until its CronJob's first tick at minute 17, so its snapshot panel has no data;
# the stage says so. It never fails the run: each `read:` line says what was read, or why it was not.
PANELS_WAIT_STEPS=${PANELS_WAIT_STEPS:-34}
PANELS_WAIT_S=${PANELS_WAIT_S:-10}
panels_read() {
  local job out state="" i q ts age
  local prom=/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query
  job=panel-check-run-$(printf '%s' "$stamp" | tr 'A-Z' 'a-z')
  if kc -n monitoring create job --from=cronjob/panel-check "$job" >/dev/null; then
    for i in $(seq 1 "$PANELS_WAIT_STEPS"); do
      out=$(kc -n monitoring get job "$job" -o 'jsonpath={.status.succeeded}/{.status.failed}' 2>/dev/null) || out=""
      case $out in 1/*) state="ended, every panel has data"; break ;; */1) state="ended with panels that have no data (the Job failed)"; break ;; esac
      [ "$i" -eq "$PANELS_WAIT_STEPS" ] || sleep "$PANELS_WAIT_S"
    done
    echo "read: panel check $job ${state:-had no result after $PANELS_WAIT_STEPS reads}"
    { kc -n monitoring logs "job/$job" 2>&1 || true; } | cut -c1-300 | head -n 60 | sed 's/^/read: /'
  else
    echo "read: panel check not run: no Job could be made from CronJob monitoring/panel-check"
  fi
  if [ -n "${OPENBAO_SEAL_KEY_FILE:-}" ]; then
    ts=$(kc -n openbao get cronjob openbao-snapshot -o 'jsonpath={.status.lastSuccessfulTime}' 2>/dev/null) || ts=""
    [ -n "$ts" ] || echo "read: no snapshot of this store has run yet (CronJob openbao/openbao-snapshot ticks at minute 17), so the snapshot panel's no data is expected"
  fi
  for q in openbao media; do
    out=$(kc get --raw "$prom?query=up%7Bnamespace%3D%22$q%22%7D" 2>/dev/null) || out=""
    printf '%s' "$out" | python3 -I -c '
import json, sys
q = sys.argv[1]
try:
    res = json.load(sys.stdin)["data"]["result"]
except Exception:
    print("read: up{namespace=\"%s\"}: not read, Prometheus did not answer through the API server" % q); sys.exit(0)
if not res:
    print("read: up{namespace=\"%s\"}: no series, Prometheus scrapes nothing there" % q)
for r in res[:10]:
    m = r.get("metric", {})
    print("read: up{namespace=\"%s\"}: job=%s pod=%s up=%s" % (q, m.get("job", "-"), m.get("pod", "-"), r.get("value", ["", "?"])[1]))
' "$q" || true
  done
  if [ -n "${OPENBAO_SEAL_KEY_FILE:-}" ]; then
    ts=$(kc -n openbao get statefulset openbao -o 'jsonpath={.metadata.creationTimestamp}' 2>/dev/null) || ts=""
    if [ -n "$ts" ] && age=$(( $(date +%s) - $(date -d "$ts" +%s 2>/dev/null || echo x) )) 2>/dev/null; then
      echo "read: StatefulSet openbao/openbao made $ts, ${age}s before this read"
    else
      echo "read: StatefulSet openbao/openbao: not read"
    fi
  else
    echo "read: StatefulSet openbao/openbao: not read, the store is not in this cluster (no OPENBAO_SEAL_KEY_FILE)"
  fi
  return 0
}

run_stage() {
  # The dev-only measurement of the agent box's source address through the Gateway (MEASURE-1): on dev with
  # the in-cluster store (its seal key file set), every render of the root Application passes openbaoMeasure,
  # so a later stage never drops it mid-run. Prod, which will set the key file too, never gets it.
  local rootvars=()
  if [ "$ENV_NAME" = dev ] && [ -n "${OPENBAO_SEAL_KEY_FILE:-}" ]; then rootvars=(-e k8s_gitops_source_openbao_measure=true); fi
  # Dev, on every render of the root Application too: no ClusterIssuer lab-ca (no `certs` stage; dev-ca comes after
  # `checks`), so jellyfin's Certificate on it would hold `apps`; and no login-probe, whose names are prod's
  # (k8s_gitops defaults, k8s_gitops_source_lab_ca_issuer and _login_probe); and no Jellyfin setup CronJob, because
  # `restore` puts prod's Jellyfin config, with prod's admin password, in place before the apps start (k8s_gitops_source_jellyfin_setup); and a suspended panel-check CronJob, whose
  # Keycloak panel has no data before the `identity-keycloak` stage; the OpenBao panels and Jellyfin's request rate
  # also printed no data in the run that failed, cause not measured (k8s_gitops_source_panel_check_suspended).
  if [ "$ENV_NAME" = dev ]; then
    rootvars+=(-e k8s_gitops_source_lab_ca_issuer=false -e k8s_gitops_source_login_probe=false -e k8s_gitops_source_jellyfin_setup=false -e k8s_gitops_source_panel_check_suspended=true)
  fi
  case $1 in
    preflight)
      [ "$ENV_NAME" = dev ] || { echo "the memory preflight runs on dev only"; return 1; }
      preflight_memory ;;
    teardown)
      tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE"
      # A targeted destroy refuses a state that still holds resources the code has moved to new addresses ("Moved
      # resource instances excluded by targeting"). A refresh-only apply writes those moves into the state and
      # changes nothing on the host, so it comes first; an untargeted destroy needs nothing.
      [ -z "${TEARDOWN_TARGET:-}" ] || tofu_k8s apply -refresh-only -auto-approve -input=false "${tofu_vars[@]}"
      tofu_k8s destroy -auto-approve -input=false ${TEARDOWN_TARGET:+"-target=$TEARDOWN_TARGET"} "${tofu_vars[@]}"
      # Set by the box's rebuild wrapper (dev only): dev's SOPS file of the apps' secrets is deleted once the state shows
      # 0 VMs. Every teardown path runs this stage, so every one reaches the hook. Unset: nothing.
      [ -z "${TEARDOWN_HOOK:-}" ] || hook "$TEARDOWN_HOOK" ;;
    vms)
      [ -z "${PRE_VMS_HOOK:-}" ] || bash -c "$PRE_VMS_HOOK"
      tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE"
      tofu_k8s apply -auto-approve -input=false "${tofu_vars[@]}" ;;
    cluster) wait_ssh && ap playbooks/k8s.yml "${kubelet_vars[@]}" ;;
    # The data disks only: Argo CD installs the provisioner and StorageClass (move-local-path-to-argo-cd.md).
    storage) ap playbooks/k8s-storage.yml --tags disk ;;
    # On dev, after the smoke test's call from this machine to the Gateway's address: every load-balancer address has
    # a node announcing it (D-0062).
    # On dev with the store in the cluster, also the node firewall rule for the store's admin path (dev only until a
    # dev run shows the admin login passing with it; the play skips without an admin address).
    gateway)
      ap playbooks/k8s-gateway.yml
      [ "$ENV_NAME" != dev ] || [ -z "${OPENBAO_SEAL_KEY_FILE:-}" ] || ap playbooks/k8s-openbao-admin-firewall.yml
      [ "$ENV_NAME" != dev ] || l2_report ;;
    # A dev re-run keeps the Gateway's HTTPS on in the root Application: the dev inventory leaves it off, and
    # flipping it off here and on again in `dev-ca` left the gateway and jellyfin apps OutOfSync for 18 minutes on
    # a re-run (measured on dev, run 8, 2026-11-14), so `apps` never finished. It does so only when the
    # certificate's Secret already exists; on a fresh build there is none yet, the Gateway would wait on it and
    # `apps` with it, so HTTPS stays off until `dev-ca` makes the Secret and turns it on.
    gitops)
      if [ "$ENV_NAME" = dev ] && kc -n gateway get secret apps-tls -o name >/dev/null 2>&1; then
        echo "gitops: the certificate's Secret exists (a re-run): the Gateway's HTTPS stays on"
        ap playbooks/k8s-gitops.yml --tags install,source -e k8s_gitops_source_gateway_https=true "${rootvars[@]}"
      else
        [ "$ENV_NAME" != dev ] || echo "gitops: no certificate Secret yet (a fresh build): the Gateway's HTTPS stays off until dev-ca"
        ap playbooks/k8s-gitops.yml --tags install,source "${rootvars[@]}"
      fi ;;
    # Seeds namespace secret-source from SECRET_SOURCE_FILE (docs/runbooks/seed-secret-source.md) after
    # Argo CD made it and before apps wait on the ExternalSecrets that read it. Unset: skipped.
    secrets)
      if [ -z "${SECRET_SOURCE_FILE:-}" ]; then echo "no SECRET_SOURCE_FILE set: secrets skipped"; return 0; fi
      [ -s "$SECRET_SOURCE_FILE" ] || { echo "SECRET_SOURCE_FILE is missing or empty"; return 1; }
      ap playbooks/k8s-secret-source.yml -e "secret_source_file=$SECRET_SOURCE_FILE" ;;
    # The secrets store inside the cluster (D-0058): its seal key on its node, before Argo CD makes the store.
    openbao-seal)
      if [ -z "${OPENBAO_SEAL_KEY_FILE:-}" ]; then echo "no OPENBAO_SEAL_KEY_FILE set: openbao-seal skipped"; return 0; fi
      [ -s "$OPENBAO_SEAL_KEY_FILE" ] || { echo "OPENBAO_SEAL_KEY_FILE is missing or empty"; return 1; }
      ap playbooks/k8s-openbao-seal.yml -e "openbao_seal_key_file=$OPENBAO_SEAL_KEY_FILE" ;;
    # Registers the cluster's service-account key with the secrets store (playbooks/k8s-openbao-auth.yml,
    # docs/runbooks/set-up-the-secrets-store.md) before apps wait on ExternalSecrets. Unset: skipped.
    openbao)
      if [ -z "${OPENBAO_ADDR:-}" ]; then echo "no OPENBAO_ADDR set: openbao skipped"; return 0; fi
      for v in OPENBAO_CACERT OPENBAO_ROLE_ID_FILE OPENBAO_SECRET_ID_FILE; do
        [ -s "${!v:-}" ] || { echo "$v is not set, or its file is missing or empty"; return 1; }
      done
      ap playbooks/k8s-openbao-auth.yml -e "openbao_url=$OPENBAO_ADDR" -e "openbao_cacert=$OPENBAO_CACERT" \
        -e "openbao_rebuild_role_id_file=$OPENBAO_ROLE_ID_FILE" -e "openbao_rebuild_secret_id_file=$OPENBAO_SECRET_ID_FILE" ;;
    # The ExternalSecret wait is dev only: it annotates every ExternalSecret, which a prod run doesn't need.
    apps) wait_apps "${APPS_DEFER:-}" && { [ "$ENV_NAME" != dev ] || wait_secrets; } ;;
    certs) ap playbooks/k8s-certs.yml ;;
    identity) ap playbooks/k8s-identity.yml ;;
    # Prod rebuilt from the agent box only, after identity: prod's Keycloak database back from its dump in the
    # snapshot the restore stage used, so accounts and their one-time-code devices come back as they were.
    identity-db)
      [ "$ENV_NAME" = prod ] || { echo "the Keycloak database is put back on prod only"; return 1; }
      ap playbooks/k8s-identity-restore.yml ;;
    # Dev only, and added to a dev run after `checks` (below): a throwaway in-cluster CA and the Gateway's
    # certificate from it, so dev has HTTPS with no prod secret (no Cloudflare token, no lab CA key).
    dev-ca)
      [ "$ENV_NAME" = dev ] || { echo "the dev CA runs on dev only"; return 1; }
      grep -q 'devca' "$repo/hosts/ansible/roles/k8s_certs/tasks/main.yml" \
        || { echo "the k8s_certs role has no devca tag: the dev CA change is missing from this checkout"; return 1; }
      # The dev inventory turns the Gateway's HTTPS off (k8s_gateway_https), so Argo CD's root Application passes
      # gatewayHttps=false and the Gateway has no https listener. Turn it on first (measured on dev, 2026-11-14:
      # spec listeners http and http-short only), then make the certificate the listener waits for.
      ap playbooks/k8s-gitops.yml --tags source -e k8s_gitops_source_gateway_https=true "${rootvars[@]}"
      ap playbooks/k8s-certs.yml --tags devca -e k8s_certs_dev_ca=true
      # The dev inventory's HTTPS off also left 443/tcp shut in each node's firewall (k8s_gateway opens it only with
      # k8s_gateway_https: roles/k8s_gateway/vars/main.yml), and Envoy takes Gateway traffic through the node's input
      # filter, so nothing reached dev's https listeners from outside. Open it now that the listener has its Secret.
      # JSON, so the value is a boolean: a key=value -e makes the string "true", which the role's `when: k8s_gateway_https`
      # refuses (ansible-core: "Conditionals must have a boolean result"; dev run 20261119T114435Z, stage dev-ca).
      ap playbooks/k8s-gateway.yml --tags gateway -e '{"k8s_gateway_https": true}' ;;
    # Dev only, after dev-ca (the https listener exists only from then on) and only with the in-cluster store:
    # the source address OpenBao sees for a box request through the Gateway, and whether c1 enforces the
    # store's NetworkPolicy (MEASURE-1, ADDENDUM-1 v3 step 1). It runs on this machine, so its requests
    # come from it. One PASS line names what it read; it changes nothing in OpenBao and prints no secret.
    openbao-measure)
      [ "$ENV_NAME" = dev ] || { echo "the measurement runs on dev only"; return 1; }
      if [ -z "${OPENBAO_SEAL_KEY_FILE:-}" ]; then echo "no OPENBAO_SEAL_KEY_FILE set: openbao-measure skipped"; return 0; fi
      ap playbooks/k8s-openbao-measure.yml ;;
    # Dev only, with the in-cluster store: the one-time hand-over of the store's admin login to this machine's
    # IDs (D-0038 rule 6). It runs on the first control-plane node; every secret goes to OpenBao's pod on stdin.
    # Until the box's address is set (k8s_gitops_source_openbao_box_cidr) it hands nothing over and says so.
    openbao-handover)
      [ "$ENV_NAME" = dev ] || { echo "the hand-over runs on dev only"; return 1; }
      if [ -z "${OPENBAO_SEAL_KEY_FILE:-}" ]; then echo "no OPENBAO_SEAL_KEY_FILE set: openbao-handover skipped"; return 0; fi
      # Neither ID file named: the box's rebuild wrapper is an install older than this stage, so nothing is
      # handed over yet. One named but missing or empty is a fault.
      if [ -z "${OPENBAO_ADMIN_ROLE_ID_FILE:-}" ] && [ -z "${OPENBAO_ADMIN_SECRET_ID_FILE:-}" ]; then
        echo "SKIP: openbao-handover: not handed over, no admin ID files named; role bootstrap stays open"; return 0
      fi
      [ -s "${OPENBAO_ADMIN_ROLE_ID_FILE:-}" ] && [ -s "${OPENBAO_ADMIN_SECRET_ID_FILE:-}" ] ||
        { echo "openbao-handover needs both OPENBAO_ADMIN_ROLE_ID_FILE and OPENBAO_ADMIN_SECRET_ID_FILE, each a file that is not empty"; return 1; }
      ap playbooks/k8s-openbao-handover.yml -e "openbao_admin_role_id_file=$OPENBAO_ADMIN_ROLE_ID_FILE" \
        -e "openbao_admin_secret_id_file=$OPENBAO_ADMIN_SECRET_ID_FILE" ;;
    # Dev only, after dev-ca: the whole identity role with a test admin, never the owner's account, then the
    # sign-in proof (password alone stops at the one-time-code form; password and code redirect with a code;
    # step names and HTTP codes only). Every secret is a random value the role makes in the values file
    # named here, identity.env in this dev env folder, so no prod file is read whichever machine runs this. The route's name proof is off: on dev the names resolve to prod's
    # Gateway, so the proof goes to this cluster's Gateway address itself. The sign-in theme is left out (Keycloak's own look): the
    # theme folder is the owner's private branding checkout, which the box doesn't hold. `signin` is also tagged never.
    # With a secrets store (OPENBAO_ADDR), the realm also gets client openbao for the store's address, and the
    # role writes openbao-oidc.json in this env folder (Keycloak's issuer, this Gateway's address, the dev CA's
    # root), for the store's owner sign-in and its proof (agent pick 233), which the in-cluster store gets later. A
    # lab-viewers user, dev-viewer, and a second lab-admins user, dev-admin2, are the ones the store must refuse.
    identity-keycloak)
      [ "$ENV_NAME" = dev ] || { echo "the dev identity stage runs on dev only"; return 1; }
      local store_host="" store_hosts="[]" handoff=""
      if [ -n "${OPENBAO_ADDR:-}" ]; then
        store_host=${OPENBAO_ADDR#https://}; store_host=${store_host%%[:/]*}
        store_hosts="[\"$store_host\"]"; handoff=$env_dir/openbao-oidc.json
      fi
      ap playbooks/k8s-identity.yml --tags all,signin \
        -e k8s_identity_owner_username=dev-admin -e k8s_identity_owner_email= \
        -e '{"k8s_identity_extra_users": [{"username": "dev-viewer", "groups": ["lab-viewers"]}, {"username": "dev-admin2", "groups": ["lab-admins"]}]}' \
        -e "{\"k8s_identity_openbao_hosts\": $store_hosts}" -e "k8s_identity_oidc_handoff_file=$handoff" \
        -e k8s_app_route_proof=false -e k8s_identity_theme_dir= -e k8s_identity_db_storage=local-path \
        -e "k8s_identity_values_file=$env_dir/identity.env" \
        -e "k8s_identity_realm_import_timeout=$DEV_REALM_IMPORT_TIMEOUT_S" \
        -e "k8s_identity_realm_import_memory=$DEV_REALM_IMPORT_MEMORY" ;;
    # Dev only, with the in-cluster store, after identity-keycloak (which writes identity.env in this env folder): SOPS's
    # copy of every value the apps read, then OpenBao's, and a compare of the two (D-0058 rule 8, plan step 8a). The box's
    # rebuild wrapper sets APP_SECRETS_HOOK only once its gate is open: the owner's sops_copies tap (D-0058 rule 9), the
    # box's admin path (box_cidr) and no rebuild hold. Shut, it sets APP_SECRETS_SKIP to the reason, and the stage prints
    # one SKIP line with it and writes nothing. Open, it also sets APP_SECRETS_CACERT, and the stage first writes this
    # run's store CA there (store_ca); a failed read fails the stage before any write. A box wrapper older than that sets
    # no APP_SECRETS_CACERT and checked its own CA file. The apps still read store c1 (appSecretsStore off).
    app-secrets)
      [ "$ENV_NAME" = dev ] || { echo "the apps' secrets stage runs on dev only"; return 1; }
      if [ -z "${OPENBAO_SEAL_KEY_FILE:-}" ]; then echo "no OPENBAO_SEAL_KEY_FILE set: app-secrets skipped"; return 0; fi
      if [ -z "${APP_SECRETS_HOOK:-}" ]; then
        echo "SKIP: app-secrets: ${APP_SECRETS_SKIP:-not run, the rebuild wrapper on the box set no gate (an install older than this stage)}"; return 0
      fi
      if [ -n "${APP_SECRETS_CACERT:-}" ]; then store_ca "$APP_SECRETS_CACERT" || return 1; fi
      hook "$APP_SECRETS_HOOK" ;;
    ui) ap playbooks/k8s-gitops.yml --tags ui,sso ;;
    backup)
      # Backup timers write to the env's restic repository; a dev run must never reach prod's.
      [ "$ENV_NAME" = prod ] || { echo "backup timers run on prod only"; return 1; }
      ap playbooks/k8s-backup.yml ;;
    restore)
      if [ -z "${RESTORE_HOOK:-}" ]; then
        # Dev proves the rebuild with prod's data in it; a skipped restore proves nothing.
        [ "$ENV_NAME" = prod ] || { echo "a dev rebuild restores prod's backup: set RESTORE_HOOK (hosts/rebuild.env.example)"; return 1; }
        echo "no RESTORE_HOOK set: restore skipped"; return 0
      fi
      hook "$RESTORE_HOOK" ;;
    checks) checks ;;
    # Dev only, after the identity stage made this run's test users: the proof for the choice of how the lab's Linux
    # boxes trust a Keycloak sign-in (OpenBao SSH certificates and opkssh, playbooks/k8s-ssh-ca-proof.yml). It uses the
    # in-cluster store's OpenBao image for its own throwaway store and never touches that store. Like `panels`, it never
    # fails the run: its "ssh-ca:" and "opkssh:" lines in the short log say what passed.
    ssh-ca-proof)
      [ "$ENV_NAME" = dev ] || { echo "the SSH sign-in proof runs on dev only"; return 1; }
      if [ -z "${OPENBAO_SEAL_KEY_FILE:-}" ]; then echo "SKIP: ssh-ca-proof: no OPENBAO_SEAL_KEY_FILE set, so no OpenBao image in this cluster"; return 0; fi
      ap playbooks/k8s-ssh-ca-proof.yml -e "k8s_identity_values_file=$env_dir/identity.env" \
        || echo "ssh-ca-proof: the playbook stopped before its result; the raw log says where"
      return 0 ;;
    panels)
      [ "$ENV_NAME" = dev ] || { echo "the panels stage runs on dev only"; return 1; }
      panels_read ;;
    *) echo "unknown stage: $1"; return 1 ;;
  esac
}

# --fit: the memory preflight alone, with PREFLIGHT_DRY: the same reads and refusals as a run's, but nothing is stopped
# (a guest a run would stop counts as its maxmem freed) and no log is written. For the box's timer, which starts a dev
# run only when this says it fits. Exit 0 fits, 3 does not or could not be read.
if $fit; then
  [ "$ENV_NAME" = dev ] || die "--fit is for dev only"
  if PREFLIGHT_DRY=true preflight_memory; then echo "fit: yes"; exit 0; fi
  echo "fit: no"; exit 3
fi

stages=${STAGES:-$default_stages}
[ -z "$only" ] || stages=${only//,/ }
# A dev run ends with its own HTTPS and sign-in proof, on the stages the box's wrapper sets, with no change to
# that wrapper: the box's own checkout of main supplies them.
# With the in-cluster store, the measurement (MEASURE-1) runs after dev-ca, which first makes the https listener,
# and the admin hand-over after it; the apps' secrets go into SOPS and OpenBao after identity-keycloak. The
# read-only `panels` stage is last on every full dev run, so its reads come before the end-of-run teardown.
if [ "$ENV_NAME" = dev ] && [ -z "$only" ]; then
  if [ -n "${OPENBAO_SEAL_KEY_FILE:-}" ]; then stages="$stages dev-ca openbao-measure openbao-handover identity-keycloak app-secrets ssh-ca-proof panels"
  else stages="$stages dev-ca identity-keycloak ssh-ca-proof panels"; fi
fi
# A dev run starts with the memory preflight, after a teardown has freed its VMs and before it makes new ones.
if [ "$ENV_NAME" = dev ] && [ -z "$only" ]; then stages="preflight $stages"; fi
if $teardown && [ -z "$only" ]; then stages="teardown $stages"; fi

# Dev only: the preflight may stop the CI runner (VM 300) to fit the dev VMs. Start it again when the run ends, pass
# or fail, and first start it if an earlier run died with it stopped (the marker file is still there).
if [ "$ENV_NAME" = dev ]; then
  runner_restart
  trap runner_restart EXIT
fi

# Dev only: what the worker's own kernel and Proxmox say while a stage runs, for the losses of 2026-11-18 13:41 UTC and
# 2026-11-19 07:20 UTC, where `kubectl top` went <unknown> with the worker at 71% working set. Two read-only probes, each
# with a hard timeout so a dead node can't hang the run, never fatal:
#   node_pressure_probe: on every node, one line each: /proc/pressure memory, cpu and io (PSI) and `free -m`'s Mem row.
#   vm_mem_probe: this run's VMs from Proxmox's /cluster/resources: the memory the host counts for each (mem, maxmem).
node_pressure_probe() { # label
  local out
  out=$(cd "$repo/hosts/ansible" && timeout "${PROBE_TIMEOUT_S:-45}" ansible k8s_nodes -i "$INVENTORY" -T 10 -o -m ansible.builtin.shell \
    -a "tr '\n' ' ' </proc/pressure/memory; tr '\n' ' ' </proc/pressure/cpu; tr '\n' ' ' </proc/pressure/io; free -m | sed -n 2p" 2>&1) || true
  if [ -n "$out" ]; then
    printf '%s\n' "$out" | cut -c1-500 | sed "s/^/  $1: node psi $(date -u +%FT%TZ) /" >> "$log" || true
  else
    echo "  $1: node psi $(date -u +%FT%TZ) no reading (timed out or no output)" >> "$log" || true
  fi
}
vm_mem_probe() { # label
  local out
  out=$(preflight_guests 2>&1 || true)   # curl's own --max-time 30 bounds it
  [ -n "$out" ] || out="preflight: no reading"
  printf '%s\n' "$out" | grep -E "guest vmid=($(printf '%s' "$ids" | tr '\n ' '||' | sed 's/|*$//'))( |$)|could not be read|unexpected shape|no reading" |
    sed "s/^preflight: /  $1: vm $(date -u +%FT%TZ) /" | cut -c1-300 >> "$log" || true
}
# On a failed ephemeral-dev run, before the teardown: each node's kernel warnings and kubelet and containerd journal of
# the last 30 minutes, when ssh still answers (an unreachable node prints one line). Secrets are scrubbed.
node_journal_diag() {
  {
    echo "== node firewall, then journals: kernel warnings, then kubelet and containerd, last 30 minutes (when ssh answers)"
    (cd "$repo/hosts/ansible" && timeout "${JOURNAL_TIMEOUT_S:-90}" ansible k8s_nodes -i "$INVENTORY" -T 10 -b -m ansible.builtin.shell \
      -a "echo '-- firewall: lab zone ports, its forward ports, policies'; firewall-cmd --zone=lab --list-ports; firewall-cmd --zone=lab --list-forward-ports; firewall-cmd --get-policies; echo '-- kernel warnings'; journalctl -k -p warning --since -30min --no-pager | tail -n 60; echo '-- kubelet and containerd'; journalctl -u kubelet -u containerd --since -30min --no-pager | tail -n 200" 2>&1) |
      python3 -I "$repo/hosts/diag-apps.py" scrub
  } 2>&1 | cut -c1-300 | head -n 500 | sed 's/^/diag: /' | tee -a "$log" >> "$raw" || true
}
# A failed ephemeral-dev run: read the cluster before it is torn down (what `rebuild diag` shows: the Argo CD
# applications and why each is not Synced and Healthy, the pods not running, the last log lines of each pod in Error,
# the newest events), into the short log, each line prefixed `diag:`. Never fatal.
runner_capture_diag() {
  echo "diag: the run failed, so the cluster is read before it is torn down" | tee -a "$log"
  {
    echo "== node CPU and memory (kubectl top nodes)"
    kc top nodes --no-headers
    echo "== argocd applications (name, sync, health)"
    kc -n argocd get applications.argoproj.io --no-headers -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
    echo "== load-balancer addresses and the nodes announcing them (D-0062)"
    l2_report || true
    echo "== cilium: host routing, masquerading, kube-proxy replacement (whether load-balancer traffic to a pod crosses the node firewall)"
    kc -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status 2>&1 | grep -iE 'host routing|masquerading|kubeproxyreplacement' | head -n 5
    echo "== pods not Running or Completed, all namespaces"
    kc get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed"'
    echo "== newest events, all namespaces"
    kc get events -A --sort-by=.lastTimestamp --no-headers | tail -n 25
    # Why an application is not Synced and Healthy: its message, its conditions and each resource that is not, then the
    # last 30 log lines of each pod in Error; both are scrubbed of secrets (hosts/diag-apps.py).
    echo "== applications not Synced and Healthy: messages and resources"
    kc -n argocd get applications.argoproj.io -o json | python3 -I "$repo/hosts/diag-apps.py" apps
    echo "== last 30 log lines of each pod in Error (at most 6 pods)"
    kc get pods -A --no-headers | awk '$4 ~ /^(Error|CrashLoopBackOff|OOMKilled|CreateContainerError|RunContainerError|Init:Error|Init:CrashLoopBackOff)$/ {print $1, $2}' | head -n 6 |
      while read -r pns pod; do
        echo "-- $pns/$pod"
        kc -n "$pns" logs "$pod" --tail=30 --all-containers=true 2>&1 | python3 -I "$repo/hosts/diag-apps.py" scrub
      done
  } 2>&1 | cut -c1-300 | head -n 260 | sed 's/^/diag: /' | tee -a "$log" >> "$raw" || true
  node_journal_diag || true
  return 0
}

# The owner's pick for a short node is ephemeral-dev: dev lasts one run. Every full run (no --only) tears dev down at its
# end, pass or fail, whether or not it had to stop VM 300. Before 2026-11-18 a run with memory to spare left dev up, and
# an agent tore it down by hand; this closes that hand step. When this run stopped VM 300,
# the exit trap then starts it under its memory rule, so VM 300 is down for one run. A run with --only tears down only
# when it stopped VM 300 itself (it has no preflight, so it never does). A failed run reads the cluster first
# (runner_capture_diag), so its state is in the log. Never on any env but dev, never with keep-dev or no setting.
runner_run_teardown() { # [failed]
  local trc t0 mine=false
  [ "$ENV_NAME" = dev ] || return 0
  [ "${PREFLIGHT_SHORT_NODE:-}" = ephemeral-dev ] || return 0
  [ -f "$(runner_mark)" ] && [ "$(cat "$(runner_mark)")" = "$stamp" ] && mine=true
  [ -z "${only:-}" ] || $mine || return 0
  if $mine; then
    echo "runner stop: this run stopped VM $CI_RUNNER_VMID and the short-node setting is ephemeral-dev, so dev is torn down now (dev can't stay up while memory is short)" | tee -a "$log"
  else
    echo "runner stop: the short-node setting is ephemeral-dev, so dev lasts one run and is torn down now" | tee -a "$log"
  fi
  [ "${1:-}" != failed ] || runner_capture_diag
  t0=$(date +%s)
  echo "$(date -u +%FT%TZ) teardown start" | tee -a "$log"
  echo "===== teardown" >> "$raw"
  set +e
  (set -e; run_stage teardown) >> "$raw" 2>&1
  trc=$?
  set -e
  echo "$(date -u +%FT%TZ) teardown end rc=$trc $(( $(date +%s) - t0 ))s" | tee -a "$log"
  return "$trc"
}

echo "rebuild: env $ENV_NAME, stages: $stages, log $log"
# The commit in the short log, so a later run can name the one it rests on (D-0035 rule 3(a): prod after dev).
echo "rebuild: central-hub $(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)" | tee -a "$log"
# Dev only, while the sign-in stage runs: each node's CPU and memory from metrics-server (kubectl top nodes), every
# 60 s, into the short log, so a slow or failed Keycloak stage shows whether the worker ran out of memory or CPU
# (the 2026-11-17 04:33 UTC run timed out with no reading). Read-only, never fatal; stopped when the stage ends, and it
# ends itself once the run's own shell is gone, so a run killed mid-stage leaves no loop behind. A sample with no
# node row logs one "no reading" line instead, with how long the call took and the first line of its error, so a gap
# in the samples says whether the call hung or failed fast, and why (the 2026-11-18 21:22 UTC run had a 352 s gap with
# no line at all).
node_top_sampler() { # stage, the run's PID
  local t t0 e rows
  while kill -0 "$2" 2>/dev/null; do
    t=$(date -u +%FT%TZ); t0=$(date +%s)
    e=$(mktemp 2>/dev/null) || e=/dev/null
    rows=$(kc top nodes --no-headers 2>"$e" \
      | awk -v s="$1" -v t="$t" 'NF >= 5 {print "  " s ": node top " t " " $1 " cpu " $3 " memory " $4 " (" $5 ")"}') || true
    if [ -n "$rows" ]; then
      printf '%s\n' "$rows" >> "$log" || true
    else
      echo "  $1: node top $t no reading after $(( $(date +%s) - t0 ))s: $(head -n 1 "$e" 2>/dev/null | cut -c 1-200 | grep . || echo 'no node row and no error')" >> "$log" || true
    fi
    [ "$e" = /dev/null ] || rm -f "$e"
    node_pressure_probe "$1"; vm_mem_probe "$1"
    sleep 60
  done
}

# A failed stage's reason, in the short log (`rebuild log`), which until now held no Ansible error: the stage's last
# Ansible task line, its fatal: and FAILED! lines and msg and stderr lines, at most 20, or the stage's last 5 lines when
# none of those exist (a stage that is not Ansible). Each line is cut at 300 characters and scrubbed of secrets by
# hosts/diag-apps.py and stripped of host names, IPv4 addresses and *.ts.net names, so the log names why a stage failed (the 2026-11-19 08:08 UTC identity-keycloak failure, 5 s, left
# only `end rc=2`). Read-only, never fatal.
stage_failure_lines() { # stage
  local sec lines
  sec=$(awk -v s="$1" '$0 == "===== " s {on=1; next} /^===== / {on=0} on' "$raw" 2>/dev/null) || true
  lines=$(printf '%s\n' "$sec" | grep -E '^TASK \[|fatal:|FAILED!|"msg"|^msg:|"stderr"|^ *stderr:' | tail -n 20) || true
  [ -n "$lines" ] || lines=$(printf '%s\n' "$sec" | grep . | tail -n 5) || true
  [ -n "$lines" ] || lines="no output from the stage in the raw log"
  # Then the names that must not reach a public record: the host in Ansible's `fatal: [host]`, every IPv4 address and
  # every *.ts.net name (hosts/diag-apps.py masks secrets, not these; CLAUDE.md rule 4 of central-hub).
  printf '%s\n' "$lines" | python3 -I "$repo/hosts/diag-apps.py" scrub 2>/dev/null |
    sed -E -e 's/(fatal|failed|unreachable|changed|ok|skipping): \[[^]]+\]/\1: [<host>]/g' \
      -e 's/[0-9]{1,3}(\.[0-9]{1,3}){3}/<ip>/g' -e 's/[A-Za-z0-9._-]+\.ts\.net/<tailnet-name>/g' |
    cut -c1-300 | sed "s/^/  $1: fail: /" >> "$log" || true
}

for s in $stages; do
  t0=$(date +%s)
  echo "$(date -u +%FT%TZ) $s start" | tee -a "$log"
  echo "===== $s" >> "$raw"
  sampler=""
  if [ "$ENV_NAME" = dev ] && [ "$s" = identity-keycloak ]; then
    node_top_sampler "$s" "$$" & sampler=$!
  fi
  # A subshell outside any `if`, so `set -e` still stops the stage at its first failed command.
  set +e
  (set -e; run_stage "$s") >> "$raw" 2>&1
  rc=$?
  set -e
  if [ -n "$sampler" ]; then kill "$sampler" 2>/dev/null || true; wait "$sampler" 2>/dev/null || true; fi
  echo "$(date -u +%FT%TZ) $s end rc=$rc $(( $(date +%s) - t0 ))s" | tee -a "$log"
  # The restore's own record (snapshot ID, each folder's files and bytes, PASS lines) goes into the
  # short log too, so the run's worklog can quote it; so does the measurement's whole PASS or SKIP line, and the
  # hand-over's PASS or SKIP line (its stage's own SKIP line is printed bare, not quoted by Ansible), and the apps'
  # secrets stage's SKIP line, or its CA line, put-apps count, compare PASS and DIFF lines (names only, never a value).
  if [ "$s" = restore ] || [ "$s" = checks ] || [ "$s" = openbao ] || [ "$s" = openbao-measure ] || [ "$s" = openbao-handover ] || [ "$s" = app-secrets ]; then
    sed -n "/^===== $s\$/,\$p" "$raw" | grep -E '"(snapshot|canary|folder|PASS|RESTORED|ALREADY|SKIP)|^SKIP: (openbao-handover|app-secrets):|^(PASS: compare:|DIFF: |secrets-store: put-apps:|app-secrets: the store.s CA written)' \
      | sed -e 's/^ *//' -e "s/^/  $s: /" >> "$log" || true
  fi
  # The SSH sign-in proof's lines: each check of each route, ok or FAIL, and its result (no secret is printed).
  if [ "$s" = ssh-ca-proof ]; then
    awk '$0 == "===== ssh-ca-proof" {on=1; next} /^===== / {on=0} on' "$raw" \
      | grep -oE '(ssh-ca|opkssh): [^"]*|SKIP: ssh-ca-proof: [^"]*|ssh-ca-proof: the playbook stopped[^"]*' \
      | sed "s/^/  $s: /" >> "$log" || true
  fi
  # The panels stage's read lines: the panel check's output, the two up reads and the store's age.
  if [ "$s" = panels ]; then
    awk '$0 == "===== panels" {on=1; next} /^===== / {on=0} on' "$raw" | grep -E '^read: ' | sed "s/^/  $s: /" >> "$log" || true
  fi
  # The gateway stage's L2 lines (D-0062): each LoadBalancer Service, its address, policy and lease holder.
  if [ "$s" = gateway ]; then
    awk '$0 == "===== gateway" {on=1; next} /^===== / {on=0} on' "$raw" | grep -E '^l2: ' | sed "s/^/  $s: /" >> "$log" || true
  fi
  # The preflight's branch and the sign-in proof's step lines (step name, HTTP code, ok or the reason; the script
  # prints nothing else) go into the short log too, so a session reading `rebuild log` sees what was proved.
  if [ "$s" = preflight ] || [ "$s" = identity-keycloak ]; then
    awk -v s="$s" '$0 == "===== " s {on=1; next} /^===== / {on=0} on' "$raw" \
      | grep -oE 'branch (skipped|checked)[^"]*|the declared dev VMs need[^"]*|node free memory[^"]*|node memory total[^"]*|node memory detail[^"]*|refused[^"]*|guest[ -]list[^"]*|storage (list|name)[^"]*|guest note[^"]*|guest vmid=[^"]*|runner (stop|restart|left stopped)[^"]*|[0-9]+ [a-z][a-z +-]*: HTTP [0-9]{3} (ok|FAIL[^"]*)' \
      | sed "s/^/  $s: /" >> "$log" || true
  fi
  if [ "$rc" -ne 0 ]; then
    stage_failure_lines "$s"
    echo "rebuild: stage $s failed; last lines of $raw:" >&2
    tail -n 20 "$raw" >&2
    runner_run_teardown failed || true
    exit "$rc"
  fi
done
runner_run_teardown || { echo "rebuild: the end-of-run teardown failed" >&2; exit 1; }
echo "rebuild: all stages passed" | tee -a "$log"
