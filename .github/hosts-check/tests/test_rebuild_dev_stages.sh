#!/usr/bin/env bash
# hosts/rebuild-k8s.sh's dev-only stages, dev-ca, openbao-measure, openbao-handover, identity-keycloak and app-secrets (its
# gate: test_rebuild_app_secrets.sh): each refuses any
# ENV_NAME other than dev before it runs Ansible, dev-ca stops with a clear message when the k8s_certs role
# has no devca tag, the measurement, its root switch and the hand-over need OPENBAO_SEAL_KEY_FILE, the hand-over
# also needs both admin ID files, and a dev run appends
# the stages after the default ones, and its PASS line reaches the short log whole. Runs run_stage from a
# copy with `ap` stubbed.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
script=$src/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^DEV_REALM_IMPORT_TIMEOUT_S=/p;/^DEV_REALM_IMPORT_MEMORY=/p;/^run_stage() {/,/^}/p' "$script" > "$t/fn.sh"
[ -s "$t/fn.sh" ] || { echo "FAIL: run_stage not found"; exit 1; }

# run_stage <env> <stage> <repo>: prints the output, and the exit code on the last line.
run() {
  ENV_NAME=$1 repo=$3 OPENBAO_ADDR=${OPENBAO_ADDR:-} env_dir=${env_dir:-} \
    OPENBAO_SEAL_KEY_FILE=${OPENBAO_SEAL_KEY_FILE:-} OPENBAO_ADMIN_ROLE_ID_FILE=${OPENBAO_ADMIN_ROLE_ID_FILE:-} \
    OPENBAO_ADMIN_SECRET_ID_FILE=${OPENBAO_ADMIN_SECRET_ID_FILE:-} bash -c '
    ap() { echo "AP $*"; }
    kc() { [ "${FAKE_SECRET:-}" = yes ]; }
    l2_report() { echo "L2 report"; }
    . "$1"
    set +e
    run_stage "$2"; echo "rc=$?"' _ "$t/fn.sh" "$2"
}
mkdir -p "$t/ok/hosts/ansible/roles/k8s_certs/tasks" "$t/bad/hosts/ansible/roles/k8s_certs/tasks"
echo "tags: [devca, never]" > "$t/ok/hosts/ansible/roles/k8s_certs/tasks/main.yml"
echo "tags: [issue]" > "$t/bad/hosts/ansible/roles/k8s_certs/tasks/main.yml"

check() { # name, output, must-contain, must-not-contain
  if [[ $2 == *"$3"* ]] && { [ -z "$4" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi
}
echo id > "$t/rid"; echo id > "$t/sid"
export OPENBAO_ADMIN_ROLE_ID_FILE=$t/rid OPENBAO_ADMIN_SECRET_ID_FILE=$t/sid
for stage in dev-ca openbao-measure openbao-handover identity-keycloak; do
  for envname in prod staging ""; do
    out=$(OPENBAO_SEAL_KEY_FILE=/k run "$envname" "$stage" "$t/ok")
    check "$stage refuses ENV_NAME='${envname}'" "$out" "rc=1" "AP "
    check "$stage says dev only for '${envname}'" "$out" "dev only" ""
  done
  out=$(OPENBAO_SEAL_KEY_FILE=/k run dev "$stage" "$t/ok")
  check "$stage runs on dev" "$out" "AP playbooks/" "rc=1"
done
# The measurement (MEASURE-1) runs only with the in-cluster store's key file, and only then does the root
# Application get openbaoMeasure; without it, and on prod, every command is as it was.
out=$(run dev openbao-measure "$t/ok")
check "openbao-measure without a key file is skipped" "$out" "openbao-measure skipped" "AP "
check "openbao-measure without a key file succeeds" "$out" "rc=0" ""
out=$(OPENBAO_SEAL_KEY_FILE=/k run dev openbao-measure "$t/ok")
check "openbao-measure with a key file runs its playbook" "$out" "AP playbooks/k8s-openbao-measure.yml" "rc=1"
# The hand-over (D-0038 rule 6) likewise, and it also needs both admin ID files, whose paths go to its playbook.
out=$(run dev openbao-handover "$t/ok")
check "openbao-handover without a key file is skipped" "$out" "openbao-handover skipped" "AP "
check "openbao-handover without a key file succeeds" "$out" "rc=0" ""
out=$(OPENBAO_SEAL_KEY_FILE=/k run dev openbao-handover "$t/ok")
check "openbao-handover passes both ID files to its playbook" "$out" "AP playbooks/k8s-openbao-handover.yml -e openbao_admin_role_id_file=$t/rid -e openbao_admin_secret_id_file=$t/sid" "rc=1"
out=$(OPENBAO_SEAL_KEY_FILE=/k OPENBAO_ADMIN_SECRET_ID_FILE=$t/none run dev openbao-handover "$t/ok")
check "openbao-handover refuses without the secret ID file" "$out" "rc=1" "AP "
out=$(OPENBAO_SEAL_KEY_FILE=/k OPENBAO_ADMIN_ROLE_ID_FILE='' run dev openbao-handover "$t/ok")
check "openbao-handover refuses without the role ID file" "$out" "rc=1" "AP "
out=$(OPENBAO_SEAL_KEY_FILE=/k OPENBAO_ADMIN_ROLE_ID_FILE='' OPENBAO_ADMIN_SECRET_ID_FILE='' run dev openbao-handover "$t/ok")
check "openbao-handover with neither ID file named (an older box wrapper) ends with a SKIP line" "$out" "SKIP: openbao-handover: not handed over, no admin ID files named" "AP "
check "openbao-handover with neither ID file named succeeds" "$out" "rc=0" "PASS"
out=$(OPENBAO_SEAL_KEY_FILE=/k run dev gitops "$t/ok")
check "dev gitops with a key file turns the measurement on" "$out" "k8s_gitops_source_openbao_measure=true" ""
out=$(OPENBAO_SEAL_KEY_FILE=/k FAKE_SECRET=yes run dev gitops "$t/ok")
check "a dev gitops re-run with a key file keeps it on" "$out" "k8s_gitops_source_openbao_measure=true" ""
out=$(OPENBAO_SEAL_KEY_FILE=/k run dev dev-ca "$t/ok")
check "dev-ca with a key file keeps it on" "$out" "k8s_gitops_source_openbao_measure=true" ""
out=$(run dev gitops "$t/ok"); check "dev gitops without a key file leaves it off" "$out" "AP " "openbao_measure"
out=$(run dev dev-ca "$t/ok"); check "dev-ca without a key file leaves it off" "$out" "AP " "openbao_measure"
out=$(OPENBAO_SEAL_KEY_FILE=/k FAKE_SECRET=yes run prod gitops "$t/ok")
check "prod gitops with a key file never turns it on" "$out" "AP playbooks/k8s-gitops.yml" "openbao_measure"
# dev-ca turns the Gateway's HTTPS on in the root Application before it makes the certificate.
out=$(run dev dev-ca "$t/ok")
check "dev-ca turns the Gateway's HTTPS on first" "$out" "k8s_gitops_source_gateway_https=true" ""
first=${out%%playbooks/k8s-certs*}
check "the HTTPS switch comes before the certificate" "$first" "k8s_gitops_source_gateway_https=true" ""
check "dev-ca opens 443 in the node firewall once HTTPS is on" "$out" "AP playbooks/k8s-gateway.yml --tags gateway -e {\"k8s_gateway_https\": true}" "k8s_gateway_https=true"
after=${out#*playbooks/k8s-certs}
check "the 443 opening comes after the certificate" "$after" "\"k8s_gateway_https\": true" ""
# The store's admin-path firewall rule: on dev with the in-cluster store only, in stage gateway, before the L2 report.
out=$(OPENBAO_SEAL_KEY_FILE=/k run dev gateway "$t/ok")
check "dev gateway with the store opens the admin path in the node firewall" "$out" "AP playbooks/k8s-openbao-admin-firewall.yml" "rc=1"
check "dev gateway still reports the L2 leases" "$out" "L2 report" ""
out=$(run dev gateway "$t/ok"); check "dev gateway without the store leaves the admin firewall alone" "$out" "AP playbooks/k8s-gateway.yml" "admin-firewall"
out=$(OPENBAO_SEAL_KEY_FILE=/k run prod gateway "$t/ok"); check "prod gateway never runs the dev admin firewall" "$out" "AP playbooks/k8s-gateway.yml" "admin-firewall"
out=$(run dev dev-ca "$t/bad")
check "dev-ca names the missing devca tag" "$out" "has no devca tag" "AP "
check "dev-ca fails without the tag" "$out" "rc=1" ""
# The dev identity stage never needs the owner's private theme folder: it passes an empty theme dir.
out=$(run dev identity-keycloak "$t/ok")
check "identity-keycloak runs with an empty theme dir" "$out" "k8s_identity_theme_dir= " ""
check "identity-keycloak puts the database on the data disk" "$out" "k8s_identity_db_storage=local-path" ""
check "identity-keycloak adds the viewer the store must refuse" "$out" '"username": "dev-viewer", "groups": ["lab-viewers"]' ""
check "identity-keycloak adds the second admin the store must refuse" "$out" '"username": "dev-admin2", "groups": ["lab-admins"]' ""
check "identity-keycloak with no store adds no openbao client" "$out" '{"k8s_identity_openbao_hosts": []}' ""
check "identity-keycloak with no store writes no handoff" "$out" "k8s_identity_oidc_handoff_file= " ""
check "identity-keycloak waits 1200 s for the realm import" "$out" "k8s_identity_realm_import_timeout=1200" ""
check "identity-keycloak caps the realm import at 1Gi" "$out" "k8s_identity_realm_import_memory=1Gi" ""
# With a store, the realm gets its address as the openbao client's name, and the handoff goes in the env folder.
out=$(OPENBAO_ADDR=https://192.0.2.10 env_dir=/env run dev identity-keycloak "$t/ok")
check "identity-keycloak with a store names it for the openbao client" "$out" '{"k8s_identity_openbao_hosts": ["192.0.2.10"]}' ""
check "identity-keycloak with a store writes the handoff in the env folder" "$out" "k8s_identity_oidc_handoff_file=/env/openbao-oidc.json" ""
# The gitops stage keeps the Gateway's HTTPS on in a dev re-run (the certificate's Secret exists), leaves it off in
# a fresh build (no Secret yet: dev-ca makes it), and prod's command is as it was.
out=$(FAKE_SECRET=yes run dev gitops "$t/ok"); check "a dev re-run keeps the Gateway's HTTPS on" "$out" "k8s_gitops_source_gateway_https=true" ""
out=$(run dev gitops "$t/ok"); check "a fresh dev build leaves it off" "$out" "AP playbooks/k8s-gitops.yml --tags install,source" "gateway_https"
check "a fresh dev build says so" "$out" "a fresh build" ""
out=$(FAKE_SECRET=yes run prod gitops "$t/ok"); check "prod gitops is unchanged" "$out" "AP playbooks/k8s-gitops.yml --tags install,source" "gateway_https"
# Dev has no ClusterIssuer lab-ca and no names of its own: every render of the root on dev turns both off, prod never.
for args in "dev gitops" "dev-fake dev gitops" "dev dev-ca"; do
  set -- $args
  if [ "$1" = dev-fake ]; then out=$(FAKE_SECRET=yes run "$2" "$3" "$t/ok"); else out=$(run "$1" "$2" "$t/ok"); fi
  check "$args: lab-ca issuer off" "$out" "-e k8s_gitops_source_lab_ca_issuer=false" ""
  check "$args: login-probe off" "$out" "-e k8s_gitops_source_login_probe=false" ""
  check "$args: jellyfin setup off" "$out" "-e k8s_gitops_source_jellyfin_setup=false" ""
  check "$args: panel check suspended" "$out" "-e k8s_gitops_source_panel_check_suspended=true" ""
  check "$args: hub feed off" "$out" "-e k8s_gitops_source_hub_feed=false" ""
done
out=$(OPENBAO_SEAL_KEY_FILE=/k run dev gitops "$t/ok")
check "dev with a key file: both off and the measurement on" "$out" "k8s_gitops_source_login_probe=false" ""
check "dev with a key file: the measurement still on" "$out" "k8s_gitops_source_openbao_measure=true" ""
# Dev's Argo CD follows the commit the run is made from: a checkout's full HEAD goes to the root's branch and to every
# child's targetRevision; no checkout (or prod) leaves `main` as it was.
git init -q "$t/gitrepo" && git -C "$t/gitrepo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m x
head=$(git -C "$t/gitrepo" rev-parse HEAD)
out=$(run dev gitops "$t/gitrepo")
check "dev gitops: the root follows the run's commit" "$out" "-e k8s_gitops_source_branch=$head" ""
check "dev gitops: the children follow it too" "$out" "-e k8s_gitops_source_target_revision=$head" ""
out=$(run dev gitops "$t/ok"); check "dev with no checkout leaves main" "$out" "AP " "source_target_revision"
out=$(FAKE_SECRET=yes run prod gitops "$t/gitrepo"); check "prod gitops leaves main" "$out" "AP " "source_target_revision"
# `backup` installs the timers only; `backup-drill` is its own stage (so a resume from `checks` can start at it) and runs the first
# backup and the restore tests, so the times `checks` reads exist. Dev refuses both, with nothing run.
out=$(run prod backup "$t/ok"); check "prod backup installs the timers only" "$out" "AP playbooks/k8s-backup.yml" "k8s_backup_drill"
out=$(run prod backup-drill "$t/ok"); check "prod backup-drill runs the drill (the first backup and restore tests)" "$out" "AP playbooks/k8s-backup.yml --tags drill -e k8s_backup_drill=true" "rc=1"
out=$(run dev backup-drill "$t/ok"); check "dev backup-drill is refused" "$out" "prod only" "AP "
out=$(run dev openbao-measure "$t/ok"); check "dev without a key file still skips the measurement" "$out" "openbao-measure skipped" "AP "
out=$(FAKE_SECRET=yes run prod gitops "$t/ok"); check "prod gitops leaves the lab-ca issuer on" "$out" "AP " "lab_ca_issuer"
check "prod gitops leaves login-probe on" "$out" "AP " "login_probe"
check "prod gitops leaves jellyfin setup on" "$out" "AP " "jellyfin_setup"
check "prod gitops leaves the hub feed on" "$out" "AP " "hub_feed"
# Prod's rebuild restores its own backup (rebuild-prod.sh sets RESTORE_HOOK), Jellyfin config and admin password with it, so its
# fresh admin Secret can't sign in (prod resume 4, 2026-11-22: 401 every tick): a prod run with a restore also turns the setup off.
out=$(RESTORE_HOOK=true FAKE_SECRET=yes run prod gitops "$t/ok")
check "prod gitops with a restore turns jellyfin setup off" "$out" "-e k8s_gitops_source_jellyfin_setup=false" ""
check "prod gitops with a restore leaves login-probe on" "$out" "AP " "login_probe"
check "prod gitops with a restore leaves the panel check running" "$out" "AP " "panel_check"
out=$(RESTORE_HOOK=true run prod gitops "$t/ok")
check "prod's first gitops with a restore turns it off too" "$out" "-e k8s_gitops_source_jellyfin_setup=false" ""
check "prod gitops leaves the panel check running" "$out" "AP " "panel_check"
# The default list stays a default: dev appends the stages only when no --only is given, and the measurement
# only with a key file, after dev-ca (which makes the https listener it goes through).
sed -n '/^if \[ "\$ENV_NAME" = dev \] && \[ -z "\$only" \]; then$/,/^fi$/p' "$script" > "$t/append.sh"
[ -s "$t/append.sh" ] || { echo "FAIL: the dev-only append block is missing or changed"; fail=1; }
appended() { # env, only, key file: the stage list after the block, starting from "base"
  ENV_NAME=$1 only=$2 OPENBAO_SEAL_KEY_FILE=$3 bash -c 'stages=base; . "$1"; echo "$stages"' _ "$t/append.sh"
}
same() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: '$2'"; fail=1; fi; }
same "a dev run without --only appends dev-ca, ui, identity-keycloak, ssh-ca-proof, identity-db and panels last" "$(appended dev "" "")" "base dev-ca ui identity-keycloak ssh-ca-proof identity-db panels"
same "with a key file ui goes after dev-ca, then the measurement, the hand-over, the apps' secrets, the SSH sign-in proof, identity-db, then panels last" "$(appended dev "" /k)" "base dev-ca ui openbao-measure openbao-handover identity-keycloak app-secrets ssh-ca-proof identity-db panels"
same "--only appends nothing" "$(appended dev gitops /k)" "base"
same "prod appends nothing" "$(appended prod "" /k)" "base"

# The measurement's PASS line goes into the short log whole: its b, b_cert and ingress fields come last.
sed -n '/^  if \[ "\$s" = restore \] .*; then$/,/^  fi$/p' "$script" > "$t/short.sh"
[ -s "$t/short.sh" ] || { echo "FAIL: the short-log block is missing or changed"; fail=1; }
long="PASS: openbao-measure: gateway=ok $(printf 'x%.0s' $(seq 1 250)); axff=400 remote=- xff=-; ingress=192.0.2.5"
printf '===== openbao-measure\n    "msg": "%s"\n' "$long" > "$t/raw"
s=openbao-measure raw=$t/raw log=$t/log bash -c '. "$1"' _ "$t/short.sh"
same "the measurement's PASS line reaches the short log whole" "$(cat "$t/log")" "  openbao-measure: \"msg\": \"$long\""
# A measurement where no probe got an answer ends with a SKIP line, which reaches the short log whole too.
: > "$t/log"
skipm="SKIP: openbao-measure: not measured, no probe got an HTTP answer from the Gateway; gateway=ok; policy=enforced; a=curl: (28) Connection timed out"
printf '===== openbao-measure\n    "msg": "%s"\n' "$skipm" > "$t/raw"
s=openbao-measure raw=$t/raw log=$t/log bash -c '. "$1"' _ "$t/short.sh"
same "the measurement's SKIP line reaches the short log whole" "$(cat "$t/log")" "  openbao-measure: \"msg\": \"$skipm\""
# The hand-over's skip is a SKIP line in the short log, never a PASS one: from its playbook, or from the stage itself.
: > "$t/log"
printf '===== openbao-handover\n    "msg": "SKIP: openbao-handover: not handed over, no box address yet; role bootstrap stays open"\n' > "$t/raw"
s=openbao-handover raw=$t/raw log=$t/log bash -c '. "$1"' _ "$t/short.sh"
same "the hand-over's SKIP line from its playbook reaches the short log" "$(cat "$t/log")" '  openbao-handover: "msg": "SKIP: openbao-handover: not handed over, no box address yet; role bootstrap stays open"'
: > "$t/log"
printf '===== openbao-handover\nSKIP: openbao-handover: not handed over, no admin ID files named; role bootstrap stays open\n' > "$t/raw"
s=openbao-handover raw=$t/raw log=$t/log bash -c '. "$1"' _ "$t/short.sh"
same "the stage's own SKIP line reaches the short log" "$(cat "$t/log")" '  openbao-handover: SKIP: openbao-handover: not handed over, no admin ID files named; role bootstrap stays open'
# Stage app-secrets: dev only, skipped without the in-cluster store's key file. Its SKIP line, put-apps count, compare
# PASS and DIFF lines reach the short log (names only); each key's own put line does not.
for envname in prod staging ""; do
  out=$(OPENBAO_SEAL_KEY_FILE=/k APP_SECRETS_HOOK='echo HOOK' run "$envname" app-secrets "$t/ok")
  check "app-secrets refuses ENV_NAME='${envname}'" "$out" "rc=1" "HOOK"
  check "app-secrets says dev only for '${envname}'" "$out" "dev only" ""
done
out=$(APP_SECRETS_HOOK='echo HOOK' run dev app-secrets "$t/ok")
check "app-secrets without a key file is skipped" "$out" "app-secrets skipped" "HOOK"
check "app-secrets without a key file succeeds" "$out" "rc=0" ""
: > "$t/log"
printf '%s\n' '===== app-secrets' "SKIP: app-secrets: sops_copies is off: SOPS copies of the apps' secrets wait for the owner's tap (D-0058 rule 9); nothing written" > "$t/raw"
s=app-secrets raw=$t/raw log=$t/log bash -c '. "$1"' _ "$t/short.sh"
same "the apps' secrets stage's SKIP line reaches the short log" "$(cat "$t/log")" "  app-secrets: SKIP: app-secrets: sops_copies is off: SOPS copies of the apps' secrets wait for the owner's tap (D-0058 rule 9); nothing written"
: > "$t/log"
printf '%s\n' '===== app-secrets' 'secrets-store put: kv/c1/identity key PASSWORD_OWNER written to SOPS, then OpenBao' \
  'secrets-store: put-apps: 3 values from rebuild-secret-source.env at c1/<name> key value, 2 from identity.env at c1/identity key <KEY>, written to SOPS, then OpenBao' \
  'DIFF: c1/ntfy-owner-password value differs' 'PASS: compare: 4 keys equal in SOPS and OpenBao' > "$t/raw"
s=app-secrets raw=$t/raw log=$t/log bash -c '. "$1"' _ "$t/short.sh"
same "the put-apps count, DIFF and compare PASS lines reach the short log, each key's put line does not" "$(cat "$t/log")" \
  "  app-secrets: secrets-store: put-apps: 3 values from rebuild-secret-source.env at c1/<name> key value, 2 from identity.env at c1/identity key <KEY>, written to SOPS, then OpenBao
  app-secrets: DIFF: c1/ntfy-owner-password value differs
  app-secrets: PASS: compare: 4 keys equal in SOPS and OpenBao"
# Stage ssh-ca-proof (RB-0295): dev only, skipped without the in-cluster store's key file, never fails the run (a failed
# playbook leaves one line), and its "ssh-ca:" and "opkssh:" lines reach the short log, the Ansible quoting dropped.
for envname in prod staging ""; do
  out=$(OPENBAO_SEAL_KEY_FILE=/k run "$envname" ssh-ca-proof "$t/ok")
  check "ssh-ca-proof refuses ENV_NAME='${envname}'" "$out" "rc=1" "AP "
  check "ssh-ca-proof says dev only for '${envname}'" "$out" "dev only" ""
done
out=$(run dev ssh-ca-proof "$t/ok")
check "ssh-ca-proof without a key file ends with a SKIP line" "$out" "SKIP: ssh-ca-proof:" "AP "
check "ssh-ca-proof without a key file succeeds" "$out" "rc=0" ""
out=$(OPENBAO_SEAL_KEY_FILE=/k env_dir=/e run dev ssh-ca-proof "$t/ok")
check "ssh-ca-proof runs its playbook with this run's identity.env" "$out" "AP playbooks/k8s-ssh-ca-proof.yml -e k8s_identity_values_file=/e/identity.env" "rc=1"
out=$(ENV_NAME=dev repo="$t/ok" OPENBAO_SEAL_KEY_FILE=/k env_dir=/e bash -c 'ap() { return 2; }; . "$1"; set +e; (set -e; run_stage ssh-ca-proof); echo "rc=$?"' _ "$t/fn.sh")
check "ssh-ca-proof whose playbook fails still passes the stage" "$out" "rc=0" ""
check "ssh-ca-proof whose playbook fails says so" "$out" "the playbook stopped before its result" ""
sed -n '/^  if \[ "\$s" = ssh-ca-proof \]; then$/,/^  fi$/p' "$script" > "$t/proof.sh"
[ -s "$t/proof.sh" ] || { echo "FAIL: the ssh-ca-proof short-log block is missing or changed"; fail=1; }
: > "$t/log"
printf '%s\n' '===== ssh-ca-proof' '    "msg": [' '        "ssh-ca: login: dev-admin'"'"'s Keycloak token gets an OpenBao token: ok",' \
  '        "opkssh: ssh: the opkssh key logs in as opkproof: ok"' '    ]' '    "msg": "ssh-ca: PASS (rc 0); opkssh: FAIL (rc 1)"' '===== panels' 'ssh-ca: not this stage' > "$t/raw"
s=ssh-ca-proof raw=$t/raw log=$t/log bash -c '. "$1"' _ "$t/proof.sh"
same "the proof's lines reach the short log, unquoted, and only its own stage's" "$(cat "$t/log")" \
  "  ssh-ca-proof: ssh-ca: login: dev-admin's Keycloak token gets an OpenBao token: ok
  ssh-ca-proof: opkssh: ssh: the opkssh key logs in as opkproof: ok
  ssh-ca-proof: ssh-ca: PASS (rc 0); opkssh: FAIL (rc 1)"
# Stages ui and identity-db on dev (item 3 of the 2026-11-22 gate order): dev's ui runs the route tag only (not sso, whose issuer name
# would be prod's), with the route and https on; another env's ui is as it was; identity-db passes the dev switch on dev only.
out=$(run dev ui "$t/ok")
check "dev ui runs the ui tag with the route and https on" "$out" 'AP playbooks/k8s-gitops.yml --tags ui -e {"k8s_gitops_ui_route": true, "k8s_gitops_ui_gateway_https": true}' "sso"
check "dev ui succeeds" "$out" "rc=0" ""
out=$(run staging ui "$t/ok")
check "a non-dev ui is the old command" "$out" "AP playbooks/k8s-gitops.yml --tags ui,sso" "k8s_gitops_ui_route"
out=$(run dev identity-db "$t/ok")
check "dev identity-db passes the dev switch" "$out" 'AP playbooks/k8s-identity-restore.yml -e {"k8s_identity_restore_dev": true}' "rc=1"
out=$(run prod identity-db "$t/ok")
check "prod identity-db passes no dev switch" "$out" "AP playbooks/k8s-identity-restore.yml" "restore_dev"
for envname in staging ""; do
  out=$(run "$envname" identity-db "$t/ok")
  check "identity-db refuses ENV_NAME='${envname}'" "$out" "rc=1" "AP "
done
exit $fail
