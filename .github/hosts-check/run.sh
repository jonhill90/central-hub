#!/usr/bin/env bash
# Run the hosts checks (STD-0005). CI runs the same commands.
# Usage: .github/hosts-check/run.sh [terraform|ansible|manifests|identity|scripts|backup|proxy|all]   (default: all)
# Needs: python3 with requirements.txt installed; tofu, tflint, kubeconform and helm on PATH, or
# TOOLS=<dir> holding them (install-tools.sh builds them); for ansible and manifests, the
# collections in hosts/ansible/requirements.yml (this script installs them when missing); for
# identity and proxy, docker (proxy: one that can run a privileged systemd container).
# TOFU_PLUGIN_DIR=<dir> makes tofu init read providers from that folder instead of the registry,
# for machines that can't download them; the copies then skip the lock file's hash check.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
here=$root/.github/hosts-check
tools=${TOOLS:-$here/.tools/bin}
[ -d "$tools" ] && PATH="$tools:$PATH"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

check_terraform() {
  # STD-0004 rules a script can see, with its own test cases.
  python3 "$here/check_hosts.py" "$root"
  bash "$here/tests/test_check_hosts.sh"
  tofu fmt -check -recursive -diff hosts/terraform
  local folder copy init_args=(-backend=false -input=false -no-color)
  [ -n "${TOFU_PLUGIN_DIR:-}" ] && init_args+=(-plugin-dir="$TOFU_PLUGIN_DIR")
  for folder in hosts/terraform/*/*/; do
    folder=${folder%/}
    ls "$folder"/*.tf >/dev/null 2>&1 || continue
    echo "== $folder"
    # Each folder runs in a copy, so .terraform/ never lands in the repo. tofu test can't import
    # under a mocked provider (OpenTofu 1.13 stops with "Importing is not supported in testing
    # context"), so the copy leaves out imports.tf. The rest of the folder is tested as written.
    copy="$work/$folder"
    mkdir -p "$copy"
    cp -r "$folder/." "$copy"
    rm -f "$copy/imports.tf"
    # Providers built from source locally don't match the lock file's hashes. CI keeps the lock.
    [ -n "${TOFU_PLUGIN_DIR:-}" ] && rm -f "$copy/.terraform.lock.hcl"
    # The shared VLAN file sits at the same path relative to the copy.
    mkdir -p "$work/hosts/ansible/inventories"
    cp -r hosts/ansible/inventories/. "$work/hosts/ansible/inventories"
    # The provider registry serves checksums from GitHub releases, which can return 504 for a while,
    # so init is tried 5 times with a growing wait, like the pip installs in hosts.yml.
    local try
    for try in 1 2 3 4 5; do
      (cd "$copy" && tofu init "${init_args[@]}" >/dev/null) && break
      [ "$try" = 5 ] && return 1
      sleep $((try * 15))
    done
    (cd "$copy" && tofu validate -no-color)
    (cd "$copy" && tflint --config "$here/tflint.hcl" --format compact)
    if ls "$copy"/tests/*.tftest.hcl >/dev/null 2>&1; then
      (cd "$copy" && tofu test -no-color)
    else
      echo "FAIL: $folder has no tests/*.tftest.hcl (STD-0005 rule 3)" >&2
      return 1
    fi
  done
}

collections() {
  [ -d hosts/ansible/collections/ansible_collections ] && return 0
  # Galaxy sometimes answers without its results list, and ansible-galaxy then keeps that broken
  # answer in its cache (seen in CI on 2026-11-08), so each try skips the cache and waits longer.
  local try
  for try in 1 2 3 4 5; do
    ansible-galaxy collection install --no-cache -r hosts/ansible/requirements.yml \
      -p hosts/ansible/collections >/dev/null && return 0
    [ "$try" = 5 ] && return 1
    sleep $((try * 15))
  done
}

check_ansible() {
  collections
  local playbook
  for playbook in hosts/ansible/playbooks/*.yml; do
    (cd hosts/ansible && ansible-playbook --syntax-check -i localhost, "${playbook#hosts/ansible/}")
  done
  (cd hosts/ansible && ansible-lint --project-dir . -c "$here/ansible-lint.yml" playbooks roles)
  python3 "$here/check-deny-rules.py"
  bash "$here/tests/test_box_apply_baseline.sh"
  python3 -I "$here/check-loop-labels.py" hosts/ansible/roles/agent_box/tasks
  bash "$here/tests/test_loop_labels.sh"
  bash "$here/tests/test_check_realm_otp.sh"
  bash "$here/tests/test_proxmox_sso.sh"
  bash "$here/tests/test_proxmox_signin_check.sh"
  bash "$here/tests/test_agent_access_rights.sh"
  bash "$here/tests/test_iac_access_pools.sh"
  bash "$here/tests/test_web_shot_modes.sh"
  bash "$here/tests/test_lab_token.sh"
  bash "$here/tests/test_sftp_key_carry.sh"
  bash "$here/tests/test_prod_lab_root.sh"
  bash "$here/tests/test_agent_browser.sh"
  bash "$here/tests/test_argocd_signin_check.sh"
  bash "$here/tests/test_proxmox_host_workflow.sh"
  bash "$here/tests/test_identity_external_secrets.sh"
  bash "$here/tests/test_identity_db_move.sh"
  bash "$here/tests/test_tailnet_stack_args.sh"
  bash "$here/tests/test_tailnet_stack_args.sh" tailnet-policy
  bash "$here/tests/test_tailnet_policy_log.sh"
  bash "$here/tests/test_tailnet_policy_sections.sh"
  bash "$here/tests/test_tailnet_policy_ledger.sh"
  bash "$here/tests/test_tailnet_stack_ledger.sh"
  bash "$here/tests/test_proxmox_host_args.sh"
  bash "$here/tests/test_opnsense_prod_args.sh"
  bash "$here/tests/test_opnsense_guard_playbook.sh"
  bash "$here/tests/test_c1_ansible.sh"
  bash "$here/tests/test_kubelet_reservations.sh"
  bash "$here/tests/test_node_probes.sh"
  bash "$here/tests/test_rebuild_failure_lines.sh"
  bash "$here/tests/test_observability_deletes.sh"
  bash "$here/tests/test_signin_check_wrapper.sh"
  bash "$here/tests/test_opnsense_cert_check.sh"
  bash "$here/tests/test_jellyfin_plugin_name.sh"
  bash "$here/tests/test_jellyfin_login_button.sh"
  bash "$here/tests/test_client_json_check.sh"
  bash "$here/tests/test_sudoers_session_args.sh"
  # A pipeline job's check run changes nothing (D-0041 rule 4): the playbooks the box's host jobs run.
  python3 "$here/check-check-mode.py" . playbooks/proxmox-proxy.yml
  bash "$here/tests/test_check_check_mode.sh"
  python3 "$here/check-hook-allowlist.py" .
  bash "$here/tests/test_runner_hook.sh"
  bash "$here/tests/test_pr_merge_verdict.sh"
  bash "$here/tests/test_pass_record.sh"
  bash "$here/tests/test_pr_merge_sweep.sh"
  bash "$here/tests/test_repo_create.sh"
  bash "$here/tests/test_checkpoint_note.sh"
  bash "$here/tests/test_checkpoint_scan.sh"
  bash "$here/tests/test_pickup_note.sh"
  bash "$here/tests/test_pickup_scan.sh"
  bash "$here/tests/test_merge_checked.sh"
  bash "$here/tests/test_lifeline_nmcli_read.sh"
  bash "$here/tests/test_lifeline_cleanup.sh"
  bash "$here/tests/test_box_apply_inventory_vars.sh"
  bash "$here/tests/test_prod_files_state_age.sh"
  bash "$here/tests/test_prod_files_lab_ca.sh"
  bash "$here/tests/test_opnsense_lab_tenant.sh"
  bash "$here/tests/test_desktop_configure_vars.sh"
  bash "$here/tests/test_opnsense_app_access.sh"
  bash "$here/tests/test_opnsense_backup_target.sh"
  bash "$here/tests/test_opnsense_store_admin.sh"
  bash "$here/tests/test_opnsense_proxmox_web.sh"
}

check_manifests() {
  collections
  local path url sum role template out extra
  # Pinned schemas, each checked against its SHA-256.
  while read -r path url sum; do
    case $path in ''|'#'*) continue ;; esac
    # A branch name in the URL lets upstream change the file under the lock: only commit SHAs.
    if [[ ! $url =~ ^https://raw\.githubusercontent\.com/[^/]+/[^/]+/[0-9a-f]{40}/ ]]; then
      echo "schemas.lock: $path is not pinned to a 40-character commit SHA: $url" >&2
      return 1
    fi
    mkdir -p "$work/schemas/$(dirname "$path")"
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 15 -o "$work/schemas/$path" "$url"
    echo "$sum  $work/schemas/$path" | sha256sum --check --quiet
  done < "$here/manifests/schemas.lock"
  mkdir -p "$work/rendered"
  while read -r role template out extra; do
    case $role in ''|'#'*) continue ;; esac
    (cd hosts/ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i localhost, \
      "$here/manifests/render.yml" -e role="$role" -e template="$template" \
      -e dest="$work/rendered/$out" -e "$extra" >/dev/null)
  done < "$here/manifests/cases.txt"
  # Each cluster's root chart, rendered as Argo CD renders it, with the made-up zone (values.yml).
  local root
  for root in hosts/kubernetes/*/*/root; do
    [ -f "$root/Chart.yaml" ] || continue
    helm lint --quiet "$root" --set zone=example.com --set gatewayAddress=192.0.2.10
    helm template root "$root" --set zone=example.com --set gatewayAddress=192.0.2.10 > "$work/rendered/root-$(basename "$(dirname "$root")").yaml"
    # The same with the pause switch on, so its sync window is schema-checked too.
    if grep -q '^  syncPaused:' "$root/values.yaml"; then
      helm template root "$root" --set zone=example.com --set gatewayAddress=192.0.2.10 --set c1Project.syncPaused=true \
        > "$work/rendered/root-$(basename "$(dirname "$root")")-paused.yaml"
    fi
  done
  # Charts kept in this repository (root values `local: true`), rendered the same way.
  local chart
  for chart in hosts/kubernetes/*/*/apps/*/Chart.yaml; do
    [ -f "$chart" ] || continue
    chart=$(dirname "$chart")
    helm lint --quiet "$chart" --set zone=example.com --set address=192.0.2.10
    helm template "$(basename "$chart")" "$chart" --namespace "$(basename "$chart")" --set zone=example.com --set address=192.0.2.10 \
      > "$work/rendered/app-$(basename "$(dirname "$(dirname "$chart")")")-$(basename "$chart").yaml"
  done
  # The secret-store app with OpenBao in the cluster turned on (dev first, D-0058), so its `openbao`
  # store and test ExternalSecret are schema-checked too.
  helm template secret-store hosts/kubernetes/home/c1/apps/secret-store --namespace external-secrets \
    --set openbao.inCluster=true \
    > "$work/rendered/app-c1-secret-store-openbao.yaml"
  # The openbao-store app with a seal node set, so the seal key's local PersistentVolume is
  # schema-checked too, and the root chart with OpenBao turned on (its two apps and the project).
  helm template openbao-store hosts/kubernetes/home/c1/apps/openbao-store --namespace openbao \
    --set sealNode=node-1 > "$work/rendered/app-c1-openbao-store-seal.yaml"
  helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 \
    --set openbaoInCluster=true --set openbaoSealNode=node-1 --set openbaoBoxCidr=192.0.2.30/32 \
    > "$work/rendered/root-c1-openbao.yaml"
  # monitoring-extras with OpenBao in the cluster: its alerts and the panel check's OpenBao lines.
  helm template monitoring-extras hosts/kubernetes/home/c1/apps/monitoring-extras --namespace monitoring \
    --set openbao.inCluster=true > "$work/rendered/app-c1-monitoring-extras-openbao.yaml"
  # The dev-only measurement of the box's path through the Gateway (MEASURE-1) turned on: the root's
  # switch and the chart it changes, so its routes and policy are schema-checked too.
  helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 \
    --set openbaoInCluster=true --set openbaoSealNode=node-1 --set openbaoBoxCidr=192.0.2.30/32 --set openbaoMeasure=true \
    > "$work/rendered/root-c1-openbao-measure.yaml"
  helm template openbao-measure hosts/kubernetes/home/c1/apps/openbao-measure --namespace openbao \
    --set zone=example.com --set measure=true > "$work/rendered/app-c1-openbao-measure-on.yaml"
  if grep -qE '^kind: (ListenerSet|TLSRoute)$' "$work/rendered/app-c1-openbao-measure-on.yaml"; then
    echo "manifests: the measurement renders a ListenerSet or TLSRoute; its passthrough path b is gone" >&2
    return 1
  fi
  # With openbaoMeasure unset, the root renders exactly as with it false, with and without OpenBao in
  # the cluster, and passes no measure switch to any app: prod's root is as before (MEASURE-1).
  local set unset
  for set in "" "--set openbaoInCluster=true --set openbaoSealNode=node-1 --set openbaoBoxCidr=192.0.2.30/32"; do
    # shellcheck disable=SC2086 # $set is a list of words on purpose
    unset=$(helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 $set)
    # shellcheck disable=SC2086
    if [ "$unset" != "$(helm template root hosts/kubernetes/home/c1/root --set zone=example.com \
      --set gatewayAddress=192.0.2.10 $set --set openbaoMeasure=false)" ]; then
      echo "manifests: the root renders differently with openbaoMeasure unset and false (${set:-default})" >&2
      return 1
    fi
    if grep -Eq -- '- name: "?(measure|centralHub\.measure|openbaoMeasure)"?$' <<<"$unset"; then
      echo "manifests: the root passes a measure switch with openbaoMeasure unset (${set:-default})" >&2
      return 1
    fi
  done
  # The store's name (openbaoStoreHost): the root with it set and the chart. Set, the store's certificate
  # names it, so the box checks the store by that name on the admin path; nothing else renders for it, since
  # the box's passthrough path through Gateway apps is gone (no ListenerSet, TLSRoute or allowedListeners).
  # Unset, the root passes no store name to any app.
  helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 \
    --set openbaoInCluster=true --set openbaoSealNode=node-1 --set openbaoStoreHost=bao.example.com \
    > "$work/rendered/root-c1-openbao-store-host.yaml"
  helm template openbao-store hosts/kubernetes/home/c1/apps/openbao-store --namespace openbao \
    --set sealNode=node-1 --set boxHost=bao.example.com > "$work/rendered/app-c1-openbao-store-host.yaml"
  if ! grep -q -- '- bao.example.com$' "$work/rendered/app-c1-openbao-store-host.yaml" ||
    grep -qE '^kind: (ListenerSet|TLSRoute|CiliumNetworkPolicy)$' "$work/rendered/app-c1-openbao-store-host.yaml" ||
    grep -q 'allowedListeners:' "$work/rendered/root-c1-openbao-store-host.yaml" "$work/rendered/app-c1-gateway.yaml"; then
    echo "manifests: with a store name, expected the name on the certificate and no ListenerSet, TLSRoute, CiliumNetworkPolicy or allowedListeners" >&2
    return 1
  fi
  if grep -q 'bao.example.com' "$work/rendered/app-c1-openbao-store.yaml" "$work/rendered/app-c1-openbao-store-seal.yaml" ||
    grep -Eq -- '- name: "?(boxHost|openbaoBoxHost)"?$' "$work/rendered/root-c1-openbao.yaml"; then
    echo "manifests: with no store name, its certificate name or a store name parameter rendered" >&2
    return 1
  fi
  # Ansible passes the store's name to the root only when it is set (cases.txt, store-host case).
  if ! grep -q 'name: openbaoStoreHost' "$work/rendered/gitops-source-argocd-openbao-store-host.yaml" ||
    grep -q 'openbaoStoreHost' "$work/rendered/gitops-source-argocd-openbao.yaml"; then
    echo "manifests: k8s_gitops should pass openbaoStoreHost only when k8s_gitops_source_openbao_store_host is set" >&2
    return 1
  fi
  if [ "$(grep -cE -- '- name: "?boxHost"?$' "$work/rendered/root-c1-openbao-store-host.yaml")" != 1 ] ||
    grep -Eq -- '- name: "?openbaoBoxHost"?$' "$work/rendered/root-c1-openbao-store-host.yaml"; then
    echo "manifests: the root with openbaoStoreHost set should pass boxHost to openbao-store only" >&2
    return 1
  fi
  # The store's admin address (openbaoAdminAddress; apps/openbao-store, admin-path.yaml; D-0062): the root
  # with it set and the chart, so the Service, the L2 announcement policy and the NetworkPolicy are
  # schema-checked. Set, the Service asks for that address with Local, the policy announces it from the
  # seal node only, and the NetworkPolicy lets the box's /32 in; unset, none of it renders and the root
  # passes no admin address. The chart refuses it without the box's /32. Role k8s_control_plane's general
  # policy must leave out the label the Service carries, or it would announce the address from every node.
  helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 \
    --set openbaoInCluster=true --set openbaoSealNode=node-1 --set openbaoBoxCidr=192.0.2.30/32 \
    --set openbaoAdminAddress=192.0.2.40 > "$work/rendered/root-c1-openbao-admin-path.yaml"
  helm template openbao-store hosts/kubernetes/home/c1/apps/openbao-store --namespace openbao \
    --set sealNode=node-1 --set boxCidr=192.0.2.30/32 --set adminAddress=192.0.2.40 \
    > "$work/rendered/app-c1-openbao-store-admin-path.yaml"
  local admin=$work/rendered/app-c1-openbao-store-admin-path.yaml admin_kinds
  admin_kinds=$(grep -E '^kind: (Service|CiliumL2AnnouncementPolicy|NetworkPolicy)$' "$admin" | sort | tr '\n' ' ')
  if [ "$admin_kinds" != "kind: CiliumL2AnnouncementPolicy kind: NetworkPolicy kind: Service " ] ||
    ! grep -q 'lbipam.cilium.io/ips: "192.0.2.40"' "$admin" || ! grep -q 'externalTrafficPolicy: Local' "$admin" ||
    ! grep -q 'kubernetes.io/hostname: "node-1"' "$admin" || ! grep -q 'cidr: 192.0.2.30/32' "$admin" ||
    ! grep -q 'central-hub/l2-policy: openbao-admin' "$admin"; then
    echo "manifests: with an admin address, expected the Service (its address, Local, the label), the policy on node-1 and the box's /32; got [$admin_kinds]" >&2
    return 1
  fi
  if grep -q 'openbao-admin' "$work/rendered/app-c1-openbao-store-seal.yaml" "$work/rendered/app-c1-openbao-store-host.yaml" ||
    grep -Eq -- '- name: "?(adminAddress|openbaoAdminAddress)"?$' "$work/rendered/root-c1-openbao.yaml" ||
    grep -q 'openbaoAdminAddress' "$work/rendered/gitops-source-argocd-openbao.yaml"; then
    echo "manifests: with no admin address, the admin path or an admin address parameter rendered" >&2
    return 1
  fi
  if ! grep -Eq -- '- name: "?adminAddress"?$' "$work/rendered/root-c1-openbao-admin-path.yaml" ||
    ! grep -q 'name: openbaoAdminAddress' "$work/rendered/gitops-source-argocd-openbao-admin.yaml" ||
    ! grep -q 'kind: CiliumL2AnnouncementPolicy' "$work/rendered/root-c1-openbao-admin-path.yaml"; then
    echo "manifests: the admin address should pass from Ansible to the root and to openbao-store, and the project allow its L2 policy" >&2
    return 1
  fi
  if helm template openbao-store hosts/kubernetes/home/c1/apps/openbao-store --namespace openbao \
    --set sealNode=node-1 --set adminAddress=192.0.2.40 >/dev/null 2>&1; then
    echo "manifests: openbao-store rendered an admin path without the box's /32" >&2
    return 1
  fi
  if ! grep -A1 -- '- key: central-hub/l2-policy$' hosts/ansible/roles/k8s_control_plane/tasks/main.yml | grep -q 'operator: DoesNotExist$'; then
    echo "manifests: role k8s_control_plane's L2 policy no longer leaves out Services labelled central-hub/l2-policy" >&2
    return 1
  fi
  # A cluster without ClusterIssuer lab-ca and with names that are not its own (dev: labCaIssuer, loginProbe
  # and jellyfinSetup false and panelCheckSuspended true, from k8s_gitops_source_lab_ca_issuer, _login_probe and _jellyfin_setup): the root passes
  # jellyfin sso.labRoot.certificate and setup.enabled false and makes no login-probe, and jellyfin then makes no Certificate on lab-ca and no setup CronJob or admin
  # Secret. c1, which leaves all three true, renders none of these changes, and Ansible passes them only when false (cases.txt).
  helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 \
    --set labCaIssuer=false --set loginProbe=false --set jellyfinSetup=false --set panelCheckSuspended=true > "$work/rendered/root-c1-dev-no-lab-ca.yaml"
  helm template monitoring-extras hosts/kubernetes/home/c1/apps/monitoring-extras --namespace monitoring \
    --set panelCheck.suspend=true > "$work/rendered/app-c1-monitoring-extras-dev-suspended.yaml"
  helm template jellyfin hosts/kubernetes/home/c1/apps/jellyfin --namespace media --set zone=example.com \
    --set sso.labRoot.certificate=false --set setup.enabled=false > "$work/rendered/app-c1-jellyfin-no-lab-ca.yaml"
  if ! grep -q 'name: "sso.labRoot.certificate"' "$work/rendered/root-c1-dev-no-lab-ca.yaml" ||
    grep -q 'name: login-probe$' "$work/rendered/root-c1-dev-no-lab-ca.yaml" ||
    grep -q 'kind: Certificate' "$work/rendered/app-c1-jellyfin-no-lab-ca.yaml" ||
    ! grep -q 'name: "setup.enabled"' "$work/rendered/root-c1-dev-no-lab-ca.yaml" ||
    ! grep -q 'name: "panelCheck.suspend"' "$work/rendered/root-c1-dev-no-lab-ca.yaml" ||
    grep -q 'panelCheck.suspend' "$work/rendered/root-c1.yaml" ||
    ! grep -qE '^  suspend: true$' "$work/rendered/app-c1-monitoring-extras-dev-suspended.yaml" ||
    ! grep -qE '^  suspend: false$' "$work/rendered/app-c1-monitoring-extras.yaml" ||
    grep -qE 'kind: CronJob|kind: ExternalSecret' "$work/rendered/app-c1-jellyfin-no-lab-ca.yaml" ||
    grep -q 'setup.enabled' "$work/rendered/root-c1.yaml" ||
    ! grep -q 'kind: CronJob' "$work/rendered/app-c1-jellyfin.yaml" ||
    grep -q 'sso.labRoot.certificate' "$work/rendered/root-c1.yaml" ||
    ! grep -q 'name: login-probe$' "$work/rendered/root-c1.yaml" ||
    ! grep -q 'kind: Certificate' "$work/rendered/app-c1-jellyfin.yaml"; then
    echo "manifests: with labCaIssuer and loginProbe false, jellyfin should get sso.labRoot.certificate false and no Certificate, and login-probe should not be made; with both true (c1), neither change" >&2
    return 1
  fi
  if ! grep -q 'name: labCaIssuer' "$work/rendered/gitops-source-argocd-dev.yaml" ||
    ! grep -q 'name: loginProbe' "$work/rendered/gitops-source-argocd-dev.yaml" ||
    ! grep -q 'name: jellyfinSetup' "$work/rendered/gitops-source-argocd-dev.yaml" ||
    ! grep -q 'name: panelCheckSuspended' "$work/rendered/gitops-source-argocd-dev.yaml" ||
    grep -qE 'labCaIssuer|loginProbe|jellyfinSetup|panelCheckSuspended' "$work/rendered/gitops-source-argocd.yaml"; then
    echo "manifests: k8s_gitops should pass labCaIssuer, loginProbe and jellyfinSetup only when they are false, and panelCheckSuspended only when true" >&2
    return 1
  fi
  # The apps' secrets read from OpenBao (appSecretsStore openbao, D-0058 rule 8): the root with it on,
  # and the three charts whose ExternalSecrets it moves, so the c1/<name> keys are schema-checked. The
  # root refuses it without OpenBao in the cluster, and refuses any other value.
  helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 \
    --set openbaoInCluster=true --set openbaoSealNode=node-1 --set appSecretsStore=openbao \
    > "$work/rendered/root-c1-app-secrets-openbao.yaml"
  helm template alerts hosts/kubernetes/home/c1/apps/alerts --namespace alerts --set zone=example.com \
    --set auth.store=openbao > "$work/rendered/app-c1-alerts-openbao.yaml"
  helm template monitoring-extras hosts/kubernetes/home/c1/apps/monitoring-extras --namespace monitoring \
    --set ntfy.store=openbao --set heartbeat.store=openbao > "$work/rendered/app-c1-monitoring-extras-secrets-openbao.yaml"
  helm template share-pod hosts/kubernetes/home/c1/apps/share-pod --namespace share-pod --set target=192.0.2.5:22 \
    --set authKey.store=openbao > "$work/rendered/app-c1-share-pod-openbao.yaml"
  local keys
  keys=$(cat "$work/rendered/app-c1-alerts-openbao.yaml" "$work/rendered/app-c1-monitoring-extras-secrets-openbao.yaml" \
    "$work/rendered/app-c1-share-pod-openbao.yaml" | grep -c 'remoteRef: {key: c1/')
  if [ "$keys" != 6 ]; then
    echo "manifests: with store openbao, expected 6 remoteRef keys under c1/, found $keys" >&2
    return 1
  fi
  # The keys those charts read, the names dev's secret-source file holds and the runbook's list agree.
  bash "$here/tests/test_app_secrets_contract.sh"
  if helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 \
    --set appSecretsStore=openbao >/dev/null 2>&1; then
    echo "manifests: the root rendered appSecretsStore openbao without openbaoInCluster" >&2
    return 1
  fi
  if helm template root hosts/kubernetes/home/c1/root --set zone=example.com --set gatewayAddress=192.0.2.10 \
    --set openbaoInCluster=true --set appSecretsStore=vault >/dev/null 2>&1; then
    echo "manifests: the root rendered an appSecretsStore other than empty, c1 or openbao" >&2
    return 1
  fi
  # Jellyfin's route sends every spelling of /metrics to the redirect.
  bash "$here/tests/test_jellyfin_metrics_route.sh"
  # c1's own alert rules: promtool checks them and runs their unit tests (rules-tests/).
  if command -v promtool >/dev/null; then
    mkdir -p "$work/rules"
    # With the OpenBao alerts on, so they are checked and tested too.
    helm template x hosts/kubernetes/home/c1/apps/monitoring-extras -n monitoring --set openbao.inCluster=true \
      -s templates/rules.yaml | python3 -c 'import sys, yaml; d = yaml.safe_load(sys.stdin); yaml.safe_dump({"groups": d["spec"]["groups"]}, sys.stdout)' \
      > "$work/rules/c1-lab.rules.yml"
    cp "$here/rules-tests/c1-lab.test.yml" "$work/rules/"
    promtool check rules "$work/rules/c1-lab.rules.yml"
    (cd "$work/rules" && promtool test rules c1-lab.test.yml)
  else
    echo "manifests: promtool not on PATH, rule tests skipped (install-tools.sh builds it)" >&2
  fi
  # What Argo CD will apply must equal what the roles apply today (parity.txt).
  python3 "$here/parity.py" . "$work"
  # What the AppProject allows must cover what every child renders (project_check.py).
  python3 "$here/project_check.py" . "$work"
  kubeconform -strict -summary -output text \
    -schema-location "$work/schemas/core/{{ .ResourceKind }}{{ .KindSuffix }}.json" \
    -schema-location "$work/schemas/crd/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json" \
    "$work/rendered"
}

check_identity() {
  # Realm lab imported into a real Keycloak in a container (identity/test_realm.sh), rendered with
  # an extra user so the users loop is tested with more than the owner, a Proxmox client (role proxmox_sso), a secrets store client (k8s_identity_openbao_hosts), an OPNsense client (k8s_identity_opnsense_hosts), and with the test sign-in
  # theme identity/theme/lab mounted the way the role mounts k8s_identity_theme_dir.
  collections
  mkdir -p "$work/identity"
  (cd hosts/ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i localhost, \
    "$here/manifests/render.yml" -e role=k8s_identity -e template=realm.yaml.j2 \
    -e dest="$work/identity/realm.yaml" \
    -e '{"k8s_identity_owner_email":"owner@example.com","k8s_identity_extra_users":[{"username":"viewer.one","groups":["lab-viewers"]}],"k8s_identity_proxmox_hosts":["pve.example.com"],"k8s_identity_openbao_hosts":["bao.example.com"],"k8s_identity_opnsense_hosts":["fw.example.com"]}' \
    -e k8s_identity_theme_dir="$here/identity/theme/lab" >/dev/null)
  bash "$here/tests/test_user_json.sh"
  bash "$here/identity/test_realm.sh" "$work/identity/realm.yaml" "$here/identity/theme/lab"
}

check_backup() {
  # The c1 backup and restore-test scripts end to end, against a real etcd and restic repository, and
  # the agent box's off-box OPNsense copy against a local restic repository.
  bash "$here/tests/test_backup.sh"
  bash "$here/tests/test_backup_azure_cert.sh"
  bash "$here/tests/test_backup_metrics.sh"
  bash "$here/tests/test_backup_repo_init.sh"
  bash "$here/tests/test_opnsense_offbox.sh"
  bash "$here/tests/test_opnsense_escrow.sh"
  bash "$here/tests/test_secrets_bundle_offbox.sh"
  bash "$here/tests/test_secrets_store_offbox.sh"
  bash "$here/tests/test_secrets_store_restore.sh"
  bash "$here/tests/test_secrets_store_snapshots.sh"
  bash "$here/tests/test_dev_secrets_teardown.sh"
  bash "$here/tests/test_dev_worker_address.sh"
  bash "$here/tests/test_proxmox_restic_reader.sh"
  bash "$here/tests/test_secrets_store_kv.sh"
  bash "$here/tests/test_secrets_store_kv_openbao.sh"
  bash "$here/tests/test_secrets_store_wrapper.sh"
  bash "$here/tests/test_openbao_prod.sh"
  bash "$here/tests/test_rebuild_prod.sh"
  bash "$here/tests/test_openbao_handover.sh"
  bash "$here/tests/test_openbao_refresh.sh"
  bash "$here/tests/test_openbao_measure.sh"
  bash "$here/tests/test_opnsense_backup_user_cleanup.sh"
  bash "$here/tests/test_opnsense_backup_keyfile.sh"
  bash "$here/tests/test_identity_signin.sh"
  bash "$here/tests/test_jellyfin_signin_check.sh"
  bash "$here/tests/test_rebuild_dev_stages.sh"
  bash "$here/tests/test_rebuild_panels.sh"
  bash "$here/tests/test_rebuild_app_secrets.sh"
  bash "$here/tests/test_rebuild_preflight.sh"
  bash "$here/tests/test_agent_access_desktop.sh"
  bash "$here/tests/test_rebuild_short_log.sh"
  bash "$here/tests/test_rebuild_l2_report.sh"
  bash "$here/tests/test_rebuild_box_inventory.sh"
  bash "$here/tests/test_rebuild_log_pick.sh"
  bash "$here/tests/test_rebuild_pin.sh"
  bash "$here/tests/test_rebuild_auto.sh"
  bash "$here/tests/test_rebuild_diag_vms.sh"
  bash "$here/tests/test_opnsense_test.sh"
  bash "$here/tests/test_lab_test.sh"
  bash "$here/tests/test_notebook_runner.sh"
}

check_proxy() {
  # Role proxmox_proxy against a stand-in Proxmox host in a container: the install beside nginx, the move from
  # nginx, its rollbacks, a run killed part-way, an open console across a graceful reload, a host with no nginx.
  bash "$here/tests/test_proxy.sh"
  # The Proxmox host as c1's restic target on the same stand-in: a real sftp backup, restore and read-only reader.
  bash "$here/tests/test_backup_sftp.sh"
  # The Proxmox host job end to end on the same stand-in (key line, check, refusal, apply), and the lifeline's
  # per-user entry loaded by nft.
  collections
  bash "$here/tests/test_proxmox_host_job.sh"
  bash "$here/tests/test_lifeline_uid.sh"
}

check_scripts() {
  # Warnings and errors fail; style notes do not (an agent pick, STD-0005).
  git ls-files -z -- '*.sh' | xargs -0 shellcheck --severity=warning
  echo "scripts: ShellCheck passed on $(git ls-files -- '*.sh' | wc -l) scripts"
  bash "$here/tests/test_c1_read.sh"
  bash "$here/tests/test_box_apply.sh"
  bash "$here/tests/test_box_user_check_group.sh"
  bash "$here/tests/test_narrow_agent_access.sh"
  bash "$here/tests/test_desktop_trust_check.sh"
  actionlint -shellcheck="$(command -v shellcheck)"
  echo "scripts: actionlint passed on $(git ls-files -- '.github/workflows/*.yml' | wc -l) workflows"
}

check_plugin_pin() {
  # The OPNsense proof's plugin package: its pinned SHA-256 and its build provenance (opnsense-plugin-pin.sh).
  bash "$here/opnsense-plugin-pin.sh"
}

case "${1:-all}" in
  terraform) check_terraform ;;
  ansible) check_ansible ;;
  manifests) check_manifests ;;
  identity) check_identity ;;
  scripts) check_scripts ;;
  backup) check_backup ;;
  proxy) check_proxy ;;
  plugin-pin) check_plugin_pin ;;
  all) check_terraform; check_ansible; check_manifests; check_identity; check_scripts; check_backup; check_proxy ;;
  *) echo "usage: $0 [terraform|ansible|manifests|identity|scripts|backup|proxy|plugin-pin|all]" >&2; exit 2 ;;
esac
