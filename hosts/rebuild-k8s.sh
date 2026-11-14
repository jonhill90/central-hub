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
#   STAGES        optional: the stages to run, in order (default below)
#   PRE_VMS_HOOK  optional: a command run before the VMs are made (Proxmox /vms ACLs, R4 step 0)
#   RESTORE_HOOK  the restore command for stage `restore`; required on dev, where it restores a
#                 read-only copy of prod's newest volume snapshot (hosts/rebuild.env.example)
#   RESTORE_CHECK_HOOK  the command the `checks` stage runs to prove the restore; required with
#                 RESTORE_HOOK
#   PREFLIGHT_MIN_FREE_MIB  optional, dev only: the least free memory (MiB) the Proxmox node must have before the VMs are made (14336)
#   APPS_TIMEOUT  optional: seconds to wait for every Argo CD app to be Synced and Healthy (1200)
#   OPENBAO_ADDR  optional: the secrets store, https://<name or address> with no path (proposed
#                 D-0038). Set: stage `openbao` registers the cluster's new service-account key with
#                 it. Unset: that stage is skipped.
#   OPENBAO_CACERT, OPENBAO_ROLE_ID_FILE, OPENBAO_SECRET_ID_FILE  with OPENBAO_ADDR: the store's
#                 certificate and the AppRole rebuild's two ID files on the controller
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
default_stages="vms cluster storage restore gitops secrets openbao apps gateway certs identity ui checks"

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

# The recap's "changed=" counts, summed over every host, from the last playbook run in $raw.
changed_total() {
  awk '/PLAY RECAP/{n=0} /changed=/{for(i=1;i<=NF;i++) if($i ~ /^changed=/){split($i,a,"="); n+=a[2]}} END{print n+0}' "$raw"
}

wait_apps() {
  local timeout=${APPS_TIMEOUT:-1200} start apps bad
  start=$(date +%s)
  while :; do
    apps=$(kc -n argocd get applications.argoproj.io --no-headers \
      -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status)
    bad=$(printf '%s\n' "$apps" | awk 'NF && ($2 != "Synced" || $3 != "Healthy")')
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

checks() {
  local notready pods
  notready=$(kc get nodes --no-headers | awk '$2 != "Ready"')
  [ -z "$notready" ] || { echo "nodes not Ready: $notready"; return 1; }
  pods=$(kc get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed"')
  [ -z "$pods" ] || { echo "pods not Running or Completed:"; echo "$pods"; return 1; }
  wait_apps
  # A second run of the cluster playbook must change nothing.
  ap "$repo/hosts/ansible/playbooks/k8s.yml" >> "$raw" 2>&1
  [ "$(changed_total)" = 0 ] || { echo "second k8s.yml run changed $(changed_total) things"; return 1; }
  # And OpenTofu must see no drift (exit 0 = no changes, 2 = changes).
  tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE" >> "$raw" 2>&1
  tofu_k8s plan -detailed-exitcode -input=false -var-file="$TFVARS" >> "$raw" 2>&1
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
# the VMs use and refuses below PREFLIGHT_MIN_FREE_MIB (default 14336: 12 GiB plus a 2 GiB margin). If the
# read fails, it refuses too: a number nobody saw is not a pass. Prints sizes in MiB only, never the token.
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
    || { echo "preflight: guest list could not be read: $(printf '%s' "$out" | tr -d '\n' | cut -c1-120)"; return 1; }
  printf '%s' "$out" | python3 -c 'import json,sys
rows = sorted(json.load(sys.stdin)["data"], key=lambda r: r.get("vmid", 0))
print("preflight: guest list from /cluster/resources?type=vm, %d guests visible to the token" % len(rows))
for r in rows:
    print("preflight: guest vmid=%s type=%s status=%s maxmem=%s MiB mem=%s MiB name=%s" % (
        r.get("vmid"), r.get("type"), r.get("status"), r.get("maxmem", 0) // 1048576, r.get("mem", 0) // 1048576,
        "".join(c for c in str(r.get("name", "")) if c.isalnum() or c in "-_.")))' \
    || { echo "preflight: guest list had an unexpected shape"; return 1; }
}

preflight_memory() {
  local min=${PREFLIGHT_MIN_FREE_MIB:-14336} node body free secret
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
  node=$(sed -n 's/^[[:space:]]*proxmox_node_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS" | head -1)
  [ -n "$node" ] || { echo "preflight: proxmox_node_name not found in the tfvars"; return 1; }
  # shellcheck source=/dev/null
  body=$( (set -a; . "$TOFU_ENV"; set +a
    insecure=(); case "${PROXMOX_VE_INSECURE:-}" in true|1) insecure=(-k) ;; esac
    # The header goes in on stdin (a curl config), so the token is never in curl's arguments, where ps shows it.
    printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
      curl -sS --fail --max-time 30 "${insecure[@]}" -K - "${PROXMOX_VE_ENDPOINT%/}/api2/json/nodes/$node/status") 2>&1) \
    || { # shellcheck source=/dev/null
         secret=$(set -a; . "$TOFU_ENV"; printf '%s' "${PROXMOX_VE_API_TOKEN##*=}")
         body=$(printf '%s' "$body" | tr -d '\n' | cut -c1-200); [ -z "$secret" ] || body=${body//"$secret"/***}
         echo "preflight: the node's memory could not be read: $body"; return 1; }
  # memory.available (the kernel's MemAvailable) exists from PVE 9; older versions have total - used.
  free=$(printf '%s' "$body" | python3 -c 'import json,sys
m = json.load(sys.stdin)["data"]["memory"]
if m.get("available") is not None:
    print(m["available"] // 1048576, "available")
else:
    print((m["total"] - m["used"]) // 1048576, "total-used")') \
    || { echo "preflight: the node's memory answer had no memory figures"; return 1; }
  field=${free#* }; free=${free% *}
  echo "preflight: node free memory ${free} MiB (field: ${field}), minimum ${min} MiB"
  preflight_guests "$node" || true
  [ "$free" -ge "$min" ] || { echo "preflight: refused, free memory ${free} MiB is below ${min} MiB"; return 1; }
}

run_stage() {
  case $1 in
    preflight)
      [ "$ENV_NAME" = dev ] || { echo "the memory preflight runs on dev only"; return 1; }
      preflight_memory ;;
    teardown)
      tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE"
      tofu_k8s destroy -auto-approve -input=false -var-file="$TFVARS" ;;
    vms)
      [ -z "${PRE_VMS_HOOK:-}" ] || bash -c "$PRE_VMS_HOOK"
      tofu_k8s init -input=false -reconfigure -backend-config="path=$TFSTATE"
      tofu_k8s apply -auto-approve -input=false -var-file="$TFVARS" ;;
    cluster) wait_ssh && ap playbooks/k8s.yml ;;
    # The data disks only: Argo CD installs the provisioner and StorageClass (move-local-path-to-argo-cd.md).
    storage) ap playbooks/k8s-storage.yml --tags disk ;;
    gateway) ap playbooks/k8s-gateway.yml ;;
    # A dev re-run keeps the Gateway's HTTPS on in the root Application: the dev inventory leaves it off, and
    # flipping it off here and on again in `dev-ca` left the gateway and jellyfin apps OutOfSync for 18 minutes on
    # a re-run (measured on dev, run 8, 2026-11-14), so `apps` never finished. It does so only when the
    # certificate's Secret already exists; on a fresh build there is none yet, the Gateway would wait on it and
    # `apps` with it, so HTTPS stays off until `dev-ca` makes the Secret and turns it on.
    gitops)
      if [ "$ENV_NAME" = dev ] && kc -n gateway get secret apps-tls -o name >/dev/null 2>&1; then
        echo "gitops: the certificate's Secret exists (a re-run): the Gateway's HTTPS stays on"
        ap playbooks/k8s-gitops.yml --tags install,source -e k8s_gitops_source_gateway_https=true
      else
        [ "$ENV_NAME" != dev ] || echo "gitops: no certificate Secret yet (a fresh build): the Gateway's HTTPS stays off until dev-ca"
        ap playbooks/k8s-gitops.yml --tags install,source
      fi ;;
    # Seeds namespace secret-source from SECRET_SOURCE_FILE (docs/runbooks/seed-secret-source.md) after
    # Argo CD made it and before apps wait on the ExternalSecrets that read it. Unset: skipped.
    secrets)
      if [ -z "${SECRET_SOURCE_FILE:-}" ]; then echo "no SECRET_SOURCE_FILE set: secrets skipped"; return 0; fi
      [ -s "$SECRET_SOURCE_FILE" ] || { echo "SECRET_SOURCE_FILE is missing or empty"; return 1; }
      ap playbooks/k8s-secret-source.yml -e "secret_source_file=$SECRET_SOURCE_FILE" ;;
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
    apps) wait_apps && { [ "$ENV_NAME" != dev ] || wait_secrets; } ;;
    certs) ap playbooks/k8s-certs.yml ;;
    identity) ap playbooks/k8s-identity.yml ;;
    # Dev only, and added to a dev run after `checks` (below): a throwaway in-cluster CA and the Gateway's
    # certificate from it, so dev has HTTPS with no prod secret (no Cloudflare token, no lab CA key).
    dev-ca)
      [ "$ENV_NAME" = dev ] || { echo "the dev CA runs on dev only"; return 1; }
      grep -q 'devca' "$repo/hosts/ansible/roles/k8s_certs/tasks/main.yml" \
        || { echo "the k8s_certs role has no devca tag: the dev CA change is missing from this checkout"; return 1; }
      # The dev inventory turns the Gateway's HTTPS off (k8s_gateway_https), so Argo CD's root Application passes
      # gatewayHttps=false and the Gateway has no https listener. Turn it on first (measured on dev, 2026-11-14:
      # spec listeners http and http-short only), then make the certificate the listener waits for.
      ap playbooks/k8s-gitops.yml --tags source -e k8s_gitops_source_gateway_https=true
      ap playbooks/k8s-certs.yml --tags devca -e k8s_certs_dev_ca=true ;;
    # Dev only, after dev-ca: the whole identity role with a test admin, never the owner's account, then the
    # sign-in proof (password alone stops at the one-time-code form; password and code redirect with a code;
    # step names and HTTP codes only). Every secret is a random value the role makes in the values file
    # named here, identity.env in this dev env folder, so no prod file is read whichever machine runs this. The route's name proof is off: on dev the names resolve to prod's
    # Gateway, so the proof goes to this cluster's Gateway address itself. The sign-in theme is left out (Keycloak's own look): the
    # theme folder is the owner's private branding checkout, which the box doesn't hold. `signin` is also tagged never.
    # With a secrets store (OPENBAO_ADDR), the realm also gets client openbao for the store's address, and the
    # role writes openbao-oidc.json in this env folder (Keycloak's issuer, this Gateway's address, the dev CA's
    # root), which `secrets-store configure` reads for the owner's sign-in and its proof (agent pick 233). A
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
        -e k8s_app_route_proof=false -e k8s_identity_theme_dir= \
        -e "k8s_identity_values_file=$env_dir/identity.env" ;;
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
    *) echo "unknown stage: $1"; return 1 ;;
  esac
}

stages=${STAGES:-$default_stages}
[ -z "$only" ] || stages=${only//,/ }
# A dev run ends with its own HTTPS and sign-in proof, on the stages the box's wrapper sets, with no change to
# that wrapper: the box's own checkout of main supplies them.
if [ "$ENV_NAME" = dev ] && [ -z "$only" ]; then stages="$stages dev-ca identity-keycloak"; fi
# A dev run starts with the memory preflight, after a teardown has freed its VMs and before it makes new ones.
if [ "$ENV_NAME" = dev ] && [ -z "$only" ]; then stages="preflight $stages"; fi
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
  # The restore's own record (snapshot ID, each folder's files and bytes, PASS lines) goes into the
  # short log too, so the run's worklog can quote it.
  if [ "$s" = restore ] || [ "$s" = checks ] || [ "$s" = openbao ]; then
    sed -n "/^===== $s\$/,\$p" "$raw" | grep -E '"(snapshot|canary|folder|PASS|RESTORED|ALREADY|SKIP)' \
      | sed -e 's/^ *//' -e "s/^/  $s: /" >> "$log" || true
  fi
  # The preflight's branch and the sign-in proof's step lines (step name, HTTP code, ok or the reason; the script
  # prints nothing else) go into the short log too, so a session reading `rebuild log` sees what was proved.
  if [ "$s" = preflight ] || [ "$s" = identity-keycloak ]; then
    awk -v s="$s" '$0 == "===== " s {on=1; next} /^===== / {on=0} on' "$raw" \
      | grep -oE 'branch (skipped|checked)[^"]*|node free memory[^"]*|refused[^"]*|guest[ -]list[^"]*|guest vmid=[^"]*|[0-9]+ [a-z][a-z +-]*: HTTP [0-9]{3} (ok|FAIL[^"]*)' \
      | sed "s/^/  $s: /" >> "$log" || true
  fi
  if [ "$rc" -ne 0 ]; then
    echo "rebuild: stage $s failed; last lines of $raw:" >&2
    tail -n 20 "$raw" >&2
    exit "$rc"
  fi
done
echo "rebuild: all stages passed" | tee -a "$log"
