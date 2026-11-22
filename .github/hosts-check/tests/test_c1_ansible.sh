#!/usr/bin/env bash
# The c1-ansible wrapper (hosts/ansible/roles/agent_box/files/c1-ansible.sh), with stand-ins for git, ansible-inventory and
# ansible-playbook:
#   1. Usage: no action, an unknown name, apply with no clearance id or a malformed one, extra arguments: exit 2, nothing run.
#   2. list names the identity playbook; a name with a private values file stops while the file is missing.
#   3. check runs the playbook with --check --diff on the box's copy of the inventory: the Mac's ssh settings and proxmox group
#      are gone, the box's key and plain ssh are set, and the values file is named to the play.
#   4. apply runs the playbook without --check, never with realm replace, and logs the clearance id; a host labelled env dev
#      refuses before any run.
#  11. clients runs the identity playbook with tags secrets,clients, the values file, no realm replace and the one fixed client; it
#      never runs the operator, database or keycloak tags; apply is its own verb and needs a clearance id.
#  12. backup-status runs its read-only playbook with no tags, no extra variables and no values file, on the box's inventory copy.
#   5. log prints the run's own lines.
#   9. users runs the identity playbook with tags secrets,users, the values file, no realm replace and one fixed user; apply is its
#      own verb; it never runs the keycloak tag.
#   8. observability runs its playbook with its fixed tags and no extra variables.
#   7. gateway runs its own playbook with a fixed tag and no extra variables; gitops with fixed tags and only k8s_gitops_source_jellyfin_setup=false
#      (prod restores its own Jellyfin config), and its CA file for the sign-in is remapped to the box's copy; no values file; certs and the install tag are not
#      names; apply needs a clearance id for them too.
#  10. The Proxmox web names (proxmox_cert_names on the proxmox group's hosts or vars) reach the box's copy as a literal
#      k8s_identity_proxmox_hosts on k8s_nodes, so the identity render has the proxmox client; the group's logins and keys
#      still do not, and with no names no such variable is written.
#   6. An inventory that names a theme folder (a controller path) is remapped to <keys>/prod/identity-theme/<its name>; with no
#      login/theme.properties there the run stops before any playbook, and with it the run goes on.
# Usage: .github/hosts-check/tests/test_c1_ansible.sh   (needs python3 with PyYAML, flock)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

venv=$t/libexec/ansible-venv/bin
mkdir -p "$t/bin" "$venv" "$t/keys/prod" "$t/work/state" "$t/work/central-hub" "$t/run"
ln -s "$(command -v python3)" "$venv/python3"
cat > "$t/bin/git" <<'S'
#!/bin/bash
case "$*" in
  *"remote get-url"*) echo https://example.invalid/central-hub.git ;;
  clone*) mkdir -p "${@: -1}/.git" "${@: -1}/hosts/ansible/playbooks"; for pb in identity gateway gitops observability certs backup-status backup-restore-test backup restore-inspect; do : > "${@: -1}/hosts/ansible/playbooks/k8s-$pb.yml"; done ;;
  *rev-parse*) echo abc1234 ;;
esac
exit 0
S
# shellcheck disable=SC2016
sed -n '/^cat > "\$venv\/ansible-inventory"/,/^EOF/p' .github/hosts-check/tests/test_openbao_prod.sh | sed "s/^EOF\$/EOF/" > "$t/inv-stub.sh"
bash -c "venv=$venv; $(cat "$t/inv-stub.sh")"
cat > "$venv/ansible-playbook" <<S
#!/bin/bash
echo "playbook \$*" >> $t/calls
cp "\${2%/}/hosts.yml" $t/seen-inventory.yml
echo "PLAY RECAP"
echo "    \"msg\": \"loki's delete would remove: nothing\""
S
chmod +x "$t/bin/git" "$venv/ansible-inventory" "$venv/ansible-playbook"
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^work=.*|work=$t/work|" \
    -e "s|PATH=\$libexec/ansible-venv/bin:/usr/local/bin|PATH=\$libexec/ansible-venv/bin:$t/bin:/usr/local/bin|" \
    -e "s|^declare -A needs_file=.*|declare -A needs_file=([identity]=\"$t/keys/prod/identity.env\" [users]=\"$t/keys/prod/identity.env\" [clients]=\"$t/keys/prod/identity.env\" [identity-values]=\"$t/keys/prod/identity.env\")|" \
    hosts/ansible/roles/agent_box/files/c1-ansible.sh > "$t/run/c1-ansible.sh"
if ! grep -q "^keys=$t/keys" "$t/run/c1-ansible.sh" || ! grep -q "identity.env" "$t/run/c1-ansible.sh"; then
  echo "FAIL the test could not point the wrapper at its folders"; exit 1
fi
run() { : > "$t/calls"; bash "$t/run/c1-ansible.sh" "$@" > "$t/out" 2>&1; rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls"); }
inventory() { printf '%s\n' "$@" > "$t/keys/prod/inventory-hosts.yml"; }
prod_inv=("all:" "  children:" "    proxmox:" "      hosts:" "        pve-a: {ansible_host: 192.0.2.1}"
          "    k8s_nodes:" "      vars:" "        ansible_ssh_common_args: -o ProxyJump=root@192.0.2.1"
          "        ansible_ssh_private_key_file: /Users/someone/.ssh/id"
          "      children:" "        k8s_control_plane:" "          hosts:" "            cp-a: {ansible_host: 192.0.2.10}")
inventory "${prod_inv[@]}"
echo node-key > "$t/keys/prod-node-key"
clr=cmsg_01X43rfNYp4H1dL1V2dkfkwNaaaaaaaaaaaaaaaaaaaaaa

r1=""
for args in "" "frob" "check" "check nope" "apply identity" "apply identity notanid" "list extra" "check identity extra"; do
  # shellcheck disable=SC2086
  run $args; r1+="$rc:${calls:-none} "
done
if [[ $r1 == "2:none 2:none 2:none 2:none 2:none 2:none 2:none 2:none " ]]; then ok "1. usage errors and unknown names, nothing run"; else bad "1. $r1"; fi

run list; l=$out
run check identity
if [[ $l == $'backup-check\nbackup-restore-test\nbackup-status\nclients\ngateway\ngitops\nidentity\nidentity-values\nobservability\nrestore-inspect\nusers' && $rc -ne 0 && $out == *"identity.env is missing"* && -z $calls ]]; then ok "2. list; a missing values file stops the run"; else bad "2. $l $rc $out"; fi

echo "X=1" > "$t/keys/prod/identity.env"
ens='{"k8s_identity_ensure_clients":["proxmox"]}'
ens_c='{"k8s_identity_ensure_clients":["proxmox","openbao","opnsense","central-hub-app"]}'   # the clients name also makes the store's, the firewall's and the Central Hub app's sign-in clients
run check identity
seen=$(cat "$t/seen-inventory.yml" 2>/dev/null)
if [[ $rc -eq 0 && $calls == *"playbooks/k8s-identity.yml -e k8s_identity_values_file=$t/keys/prod/identity.env -e k8s_identity_realm_replace=false k8s_identity_secrets_store=openbao --tags all,clients -e $ens --check --diff" &&
      $seen != *ProxyJump* && $seen != */Users/* && $seen != *pve-a* && $seen == *"$t/keys/prod-node-key"* ]]; then
  ok "3. check: --check --diff on the box's copy of the inventory"
else bad "3. $rc [$calls] $out"; fi

run apply identity "$clr"
if [[ $rc -eq 0 && $calls != *--check* && $calls == *"playbooks/k8s-identity.yml -e k8s_identity_values_file="* && $calls == *"-e k8s_identity_realm_replace=false k8s_identity_secrets_store=openbao"* && $calls == *"--tags all,clients"* && $calls == *"$ens"* && $out == *"clearance $clr"* ]]; then
  ok "4a. apply: no --check, the clearance id logged"
else bad "4a. $rc [$calls] $out"; fi
inventory "${prod_inv[@]}" "            cp-b: {ansible_host: 192.0.2.11, k8s_gitops_cluster_labels: {env: dev}}"
run apply identity "$clr"
if [[ $rc -ne 0 && -z $calls && $out == *"not prod"* ]]; then ok "4b. a host labelled env dev refuses before any run"; else bad "4b. $rc [$calls] $out"; fi

inventory "${prod_inv[@]}"
run check identity; run log
if [[ $rc -eq 0 && $out == *"c1-ansible: check identity at central-hub abc1234"* && $out == *"PLAY RECAP"* && $out == *"delete would remove: nothing"* ]]; then ok "5. log prints the run's own lines, and the delete-would-remove lines"; else bad "5. $rc $out"; fi

inventory "all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_identity_theme_dir: /Users/someone/branding/example-theme/" "      children:" "        k8s_control_plane:" "          hosts:" "            cp-a: {ansible_host: 192.0.2.10}"
run check identity; r6a="$rc:${calls:-none}:$out"
mkdir -p "$t/keys/prod/identity-theme/example-theme/login"; echo "parent=keycloak.v2" > "$t/keys/prod/identity-theme/example-theme/login/theme.properties"
run check identity; seen=$(cat "$t/seen-inventory.yml" 2>/dev/null)
if [[ $r6a == 1:none:*"no login/theme.properties on the box"* && $r6a == *"$t/keys/prod/identity-theme/example-theme"* ]] &&
   [[ $rc -eq 0 && $seen == *"k8s_identity_theme_dir: $t/keys/prod/identity-theme/example-theme"* && $seen != */Users/* ]]; then
  ok "6. the theme folder is remapped to the box's copy; a missing copy stops the run first"
else bad "6. [$r6a] $rc [$calls] $out"; fi
inventory "${prod_inv[@]}"
run check gateway; g1=$calls
run check gitops; g2=$calls
run apply gateway "$clr"; g3=$calls; g3rc=$rc
run apply gitops "$clr"; g4=$calls; g4o=$out
if [[ $g1 == *"playbooks/k8s-gateway.yml --tags gateway --check --diff" && $g1 != *" -e "* &&
      $g2 == *"playbooks/k8s-gitops.yml -e k8s_gitops_source_jellyfin_setup=false --tags source,ui,sso --check --diff" &&
      $g3rc -eq 0 && $g3 == *"playbooks/k8s-gateway.yml --tags gateway" && $g3 != *--check* &&
      $g4 == *"playbooks/k8s-gitops.yml -e k8s_gitops_source_jellyfin_setup=false --tags source,ui,sso" && $g4 != *--check* && $g4o == *"clearance $clr"* ]]; then
  ok "7a. gateway: own playbook, fixed tag, no extra variables; gitops: fixed tags and only jellyfin setup off (prod restores its own Jellyfin config); apply is its own verb"
else bad "7a. [$g1] [$g2] [$g3] [$g4]"; fi
# 7c: the sign-in's CA file names a path on the controller; the box's copy is <keys>/prod/lab-ca/root.crt (rebuild-prod.sh maps it the same way).
inventory "all:" "  children:" "    k8s_nodes:" "      vars:" "        k8s_gitops_sso: true" "        k8s_gitops_sso_root_ca_file: ~/.config/central-hub/lab-ca/root.crt" "      children:" "        k8s_control_plane:" "          hosts:" "            cp-a: {ansible_host: 192.0.2.10}"
run check gitops; seen=$(cat "$t/seen-inventory.yml" 2>/dev/null)
if [[ $rc -eq 0 && $seen == *"k8s_gitops_sso_root_ca_file: $t/keys/prod/lab-ca/root.crt"* && $seen != *".config/central-hub"* && $seen == *"k8s_gitops_sso: true"* ]]; then
  ok "7c. the sign-in's CA file is remapped to the box's copy under <keys>/prod/lab-ca; the sso switch is kept as the inventory has it"
else bad "7c. $rc [$calls] $out | $seen"; fi
inventory "${prod_inv[@]}"
r7=""
for args in "check certs" "check k8s-certs" "apply certs $clr" "check gitops-install" "apply gateway" "apply gitops badid"; do
  # shellcheck disable=SC2086
  run $args; r7+="$rc:${calls:-none} "
done
if [[ $r7 == "2:none 2:none 2:none 2:none 2:none 2:none " ]]; then ok "7b. certs and install are not names; apply needs a clearance id"; else bad "7b. $r7"; fi
run check backup-status; b1=$calls; b1rc=$rc
if [[ $b1rc -eq 0 && $b1 == *"playbooks/k8s-backup-status.yml --check --diff" && $b1 != *" -e "* && $b1 != *--tags* ]]; then
  ok "12. backup-status: its own playbook, no tags, no extra variables"
else bad "12. $b1rc [$b1]"; fi
grep -q "check_mode: false" hosts/ansible/playbooks/k8s-backup-status.yml && ! grep -E "^\s+(ansible.builtin.(copy|file|template|systemd|service|lineinfile)):" hosts/ansible/playbooks/k8s-backup-status.yml >/dev/null \
  && ok "12b. the playbook only reads: every command task is check_mode false and none writes a file or service" || bad "12b. the playbook writes"
echo stale-key > "$t/work/c1-ansible/known_hosts" 2>/dev/null || { mkdir -p "$t/work/c1-ansible"; echo stale-key > "$t/work/c1-ansible/known_hosts"; }
run check restore-inspect; i1=$calls; i1rc=$rc; k1=$(ls "$t/work/c1-ansible/known_hosts" 2>/dev/null)
printf '%s\n' 36fe4321aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa > "$t/work/state/prod-restore-pin"
run check restore-inspect; i2=$calls
rm -f "$t/work/state/prod-restore-pin"
if [[ $i1rc -eq 0 && $i1 == *"playbooks/k8s-restore-inspect.yml --check --diff" && $i1 != *" -e "* && $i1 != *--tags* && -z $k1 &&
      $i2 == *"-e restore_inspect_snapshot=36fe4321aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"* ]]; then
  ok "12c. restore-inspect: its own playbook, no tags, starts from no known hosts, takes the restore pin as the snapshot when the box holds one"
else bad "12c. $i1rc [$i1] [$k1] [$i2]"; fi
grep -q "check_mode: false" hosts/ansible/playbooks/k8s-restore-inspect.yml && ! grep -E "^\s+(ansible.builtin.(copy|file|template|systemd|service|lineinfile)):" hosts/ansible/playbooks/k8s-restore-inspect.yml >/dev/null \
  && ok "12d. the restore-inspect playbook only reads" || bad "12d. the restore-inspect playbook writes"
run check backup-restore-test; r1=$calls; run apply backup-restore-test "$clr"; r2=$calls; r2rc=$rc
if [[ $r1 == *"playbooks/k8s-backup-restore-test.yml --check --diff" && $r2rc -eq 0 && $r2 == *"playbooks/k8s-backup-restore-test.yml" && $r2 != *--check* && $r1$r2 != *" -e "* && $r1$r2 != *--tags* ]]; then
  ok "13. backup-restore-test: own playbook, no tags or extra variables, check starts nothing, apply needs a clearance id"
else bad "13. [$r1] [$r2]"; fi
run apply backup-restore-test; [[ $rc -eq 2 && -z $calls ]] && ok "13b. apply backup-restore-test without a clearance id runs nothing" || bad "13b. $rc [$calls]"
cat > "$t/bin/ssh" <<'S'
#!/bin/bash
echo "ssh $*" >> "$SSH_LOG"
case "${*: -1}" in *"cat /etc/central-hub/backup-ssh/known_hosts") echo "c1-backup-target ssh-ed25519 AAAAfakehostkey" ;; *) exit 1 ;; esac
S
chmod +x "$t/bin/ssh"; export SSH_LOG="$t/sshcalls"; : > "$SSH_LOG"
run check backup-check; bc1=$calls; bc1rc=$rc; bc1out=$out
run apply backup-check "$clr"; bc2rc=$rc bc2=$calls
if [[ $bc1rc -eq 0 && $bc1 == *"playbooks/k8s-backup.yml"* && $bc1 == *"-e k8s_backup_env_file=$t/keys/c1-backup.env"* && $bc1 == *"--check --diff" &&
      $bc2rc -eq 2 && -z $bc2 && $(grep -c 'k8s_backup_sftp_seed_dir: .*/backup-check-seed' "$t/seen-inventory.yml") -ge 1 &&
      $bc1out == *"pinned host key was read from 1 node(s) (public keys only)"* && $bc1out == *"the host address was NOT found"* &&
      $(cat "$t/work/state/backup-check-seed/cp-a.known_hosts") == "c1-backup-target ssh-ed25519 AAAAfakehostkey" &&
      $(grep -c 'cat /etc/central-hub/backup-ssh/id_ed25519\|\.pub' "$SSH_LOG") -eq 0 ]]; then
  ok "14. backup-check: the backup playbook in check mode with the box's own env file and the seed folder; apply is refused"
else bad "14. $bc1rc [$bc1] $bc2rc [$bc2]"; fi
run check observability; o1=$calls
run apply observability "$clr"; o2=$calls; o2rc=$rc; o2o=$out
if [[ $o1 == *"playbooks/k8s-observability.yml --tags metrics_server,metrics,logs,route,proof --check --diff" && $o1 != *" -e "* &&
      $o2rc -eq 0 && $o2 == *"playbooks/k8s-observability.yml --tags metrics_server,metrics,logs,route,proof" && $o2 != *--check* && $o2o == *"clearance $clr"* ]]; then
  ok "8. observability: own playbook, fixed tags, no extra variables, apply is its own verb"
else bad "8. [$o1] [$o2]"; fi
run check users; u1=$calls; u1rc=$rc
run apply users "$clr"; u2=$calls; u2rc=$rc; u2o=$out
uj='{"k8s_identity_ensure_users":["signin-test"]}'
if [[ $u1rc -eq 0 && $u1 == *"playbooks/k8s-identity.yml -e k8s_identity_values_file=$t/keys/prod/identity.env -e k8s_identity_realm_replace=false k8s_identity_secrets_store=openbao --tags secrets,users -e $uj --check --diff" &&
      $u2rc -eq 0 && $u2 == *"--tags secrets,users -e $uj" && $u2 != *--check* && $u2 != *keycloak* && $u2 != *all* && $u2o == *"clearance $clr"* ]]; then
  ok "9. users: identity playbook, tags secrets,users, one fixed user, no realm replace, apply is its own verb"
else bad "9. [$u1] [$u2]"; fi
echo "X=1" > "$t/keys/prod/identity.env"
inventory "all:" "  children:" "    proxmox:" "      vars: {proxmox_cert_names: [pve.vars.example.test]}" "      hosts:" "        pve-a: {ansible_host: 192.0.2.1, proxmox_cert_names: [pve.host.example.test, pve.vars.example.test], ansible_ssh_common_args: -o ProxyJump=root@192.0.2.1}" \
          "    k8s_nodes:" "      vars:" "        k8s_identity_proxmox_hosts: \"{{ hostvars['proxmox_host'].proxmox_cert_names }}\"" "      children:" "        k8s_control_plane:" "          hosts:" "            cp-a: {ansible_host: 192.0.2.10}"
run check identity; seen=$(cat "$t/seen-inventory.yml" 2>/dev/null)
names=$(python3 -I -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); print(d["all"]["children"]["k8s_nodes"]["vars"]["k8s_identity_proxmox_hosts"])' "$t/seen-inventory.yml" 2>&1)
if [[ $rc -eq 0 && $names == "['pve.host.example.test', 'pve.vars.example.test']" && $seen != *pve-a* && $seen != *ProxyJump* && $seen != *hostvars* &&
      $out == *"2 Proxmox web names"* && $out != *example.test* ]]; then
  ok "10a. the Proxmox web names reach k8s_nodes as a literal, nothing else of the group does, and only a count is printed"
else bad "10a. $rc [$names] $out"; fi
inventory "${prod_inv[@]}"
run check identity; seen=$(cat "$t/seen-inventory.yml" 2>/dev/null)
if [[ $rc -eq 0 && $seen != *k8s_identity_proxmox_hosts* && $out != *"Proxmox web names"* ]]; then ok "10b. no names in the proxmox group: no variable written"; else bad "10b. $rc $out"; fi
run check clients; c1=$calls; c1rc=$rc
run apply clients "$clr"; c2=$calls; c2rc=$rc; c2o=$out
run apply clients; c3rc=$rc; c3=$calls
run check identity-values; iv1rc=$rc; iv1=$calls
run apply identity-values "$clr"; iv2rc=$rc; iv2=$calls
run apply identity-values; iv3rc=$rc; iv3=$calls
if [[ $iv1rc -eq 2 && -z $iv1 && $iv2rc -eq 0 && $iv2 == *"playbooks/k8s-identity.yml -e k8s_identity_values_file=$t/keys/prod/identity.env --tags always" && $iv2 != *--check* &&
      $iv2 != *clients* && $iv2 != *secrets* && $iv3rc -ne 0 && -z $iv3 ]]; then
  ok "11c. identity-values: identity playbook, tags always only (the values file's missing keys), no check, apply needs a clearance id"
else bad "11c. $iv1rc [$iv1] $iv2rc [$iv2] $iv3rc"; fi
if [[ $c1rc -eq 0 && $c1 == *"playbooks/k8s-identity.yml -e k8s_identity_values_file=$t/keys/prod/identity.env -e k8s_identity_realm_replace=false k8s_identity_secrets_store=openbao --tags secrets,clients -e $ens_c --check --diff" &&
      $c2rc -eq 0 && $c2 == *"--tags secrets,clients -e $ens_c" && $c2 != *--check* && $c2 != *keycloak* && $c2 != *operator* && $c2 != *database* && $c2 != *all* &&
      $c2o == *"clearance $clr"* && $c3rc -eq 2 && -z $c3 ]]; then
  ok "11. clients: identity playbook, tags secrets,clients, one fixed client, no realm replace, apply needs a clearance id"
else bad "11. [$c1] [$c2] $c3rc"; fi
rm -f "$t/keys/prod/identity.env"
run check users
if [[ $rc -ne 0 && $out == *"identity.env is missing"* && -z $calls ]]; then ok "9b. users stops while the values file is missing"; else bad "9b. $rc $out"; fi
exit "$fail"
