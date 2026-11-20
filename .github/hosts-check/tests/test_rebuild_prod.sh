#!/usr/bin/env bash
# The rebuild-prod wrapper's own checks (hosts/ansible/roles/agent_box/files/rebuild-prod.sh), with stand-ins for git,
# tofu, ssh, sops, ansible-inventory, ansible-playbook, the box's off-box jobs and hosts/rebuild-k8s.sh:
#   1. Usage: no action, another action, rebuild with no tap id or a malformed one: usage errors, nothing run.
#   2. check with nothing on the box names what is missing and changes nothing.
#   3. check with everything in place passes every line: the box's state is the live prod, the teardown destroys
#      only VMs 200 and 201, every node answers, the box routes around the nodes, and dev passed at this commit.
#   4. The box's inventory copy: the box's key and plain ssh, the private files at the box's copies, the rebuild's
#      own settings (prod's own restore, stable folders, the carried certificates, the store's admin address), no proxmox
#      group.
#   5. check refuses, each alone: a plan with changes, a teardown that would destroy VM 258, a value still on the
#      Mac, a dev run at another commit, a failed dev run, a node VM ID outside 200-249, the box's route to the
#      Proxmox API or its default route through a prod node.
#   6. rebuild runs the checks before a teardown in order (backup and restore test, the certificates, the seal
#      key, the firewall copy, the bundle), keeps each node's certificate, then the one command with prod's stages,
#      the seal key in memory, and the tap id in the log.
#   7. rebuild with a seal key that differs from the node's, a failed backup test, or a drill whose restore tests
#      name no snapshot (a node with nothing to test), destroys nothing.
#   8. log prints the run's lines.
#   9. The Mac's inventory with no labels gets the role's default (env prod); the sign-in CA is mapped.
#  10. The sign-in theme folder keeps its own name under prod/identity-theme/; one with no login/theme.properties is refused.
#  11. rebuild builds the commit the go names, which must be on main; check reads main's newest.
#  12. The backup target: sftp to the Proxmox host is refused at check; with no Azure sign-in no certificate is carried.
#  13. rebuild refuses a commit older than the floor (PIN_FLOOR, the same as the dev wrapper's), before anything runs.
# Usage: .github/hosts-check/tests/test_rebuild_prod.sh   (needs python3 with PyYAML, ssh-keygen, flock)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"; rm -rf /dev/shm/rebuild-prod-seal.test-*' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
sha=0123456789abcdef0123456789abcdef01234567

venv=$t/libexec/ansible-venv/bin
mkdir -p "$t/bin" "$venv" "$t/keys/prod/tfvars" "$t/keys/prod/state" "$t/keys/secrets-bundle" "$t/work/state" \
  "$t/work/central-hub" "$t/work/rebuild-dev/logs" "$t/run"
ln -s "$(command -v python3)" "$venv/python3"
cat > "$t/bin/git" <<EOF
#!/bin/bash
case "\$*" in
  *"remote get-url"*) echo https://example.invalid/central-hub.git ;;
  clone*) d="\${@: -1}"; mkdir -p "\$d/.git" "\$d/hosts/ansible/roles/k8s_gitops/defaults" "\$d/hosts/terraform/home/k8s"
          printf '%s\n' 'k8s_gitops_cluster_labels:' '  place: home' '  env: prod' '  purpose: apps' > "\$d/hosts/ansible/roles/k8s_gitops/defaults/main.yml"
          printf '%s\n' '#!/bin/bash' 'echo "one-command \$*" >> $t/calls' 'cp "\$1/rebuild.env" $t/seen-rebuild.env' \
            'f=\$(sed -n "s/^OPENBAO_SEAL_KEY_FILE=//p" "\$1/rebuild.env"); [ -s "\$f" ] && echo "seal-in-memory \$(wc -c < "\$f")" >> $t/calls' \
            'exit \${ONE_RC:-0}' > "\$d/hosts/rebuild-k8s.sh" ;;
  *"rev-parse --quiet --verify "*) a="\${*: -1}"; a="\${a%^\{commit\}}"; [[ $sha == "\$a"* ]] && echo $sha || exit 1 ;;
  *rev-parse*) echo $sha ;;
  *"merge-base --is-ancestor "*" origin/main") exit \${NOT_ON_MAIN:-0} ;;
  *"merge-base --is-ancestor "*) echo "floor \$5 \$6" >> $t/floorcalls; exit \${BELOW_FLOOR:-0} ;;
  *" checkout "*) echo "git \${*: -1}" >> $t/gitcalls ;;
esac
exit 0
EOF
cat > "$t/bin/tofu" <<EOF
#!/bin/bash
echo "tofu \${*:2}" >> $t/calls
case " \$* " in
  *" init "*) [ -z "\${TOFU_INIT_TEXT:-}" ] || echo "\$TOFU_INIT_TEXT"; exit \${TOFU_INIT_RC:-0} ;;
  *" apply "*) exit \${TOFU_APPLY_RC:-0} ;;
  *" show "*) cat \${TOFU_SHOW_FILE:-$t/destroy.json}; exit 0 ;;
  *" -destroy "*) for a in "\$@"; do case \$a in -out=*) : > "\${a#-out=}" ;; esac; done; exit 0 ;;
  *" plan "*) exit \${TOFU_PLAN_RC:-0} ;;
esac
EOF
# ssh: the last argument is the command; each answers as a node would.
cat > "$t/bin/getent" <<'EOF'
#!/bin/bash
case $2 in pve.invalid) echo "192.0.2.1       STREAM pve.invalid" ;; *) [[ $2 =~ ^[0-9.]+$ ]] && echo "$2       STREAM $2" ;; esac
exit 0
EOF
cat > "$t/bin/ip" <<'EOF'
#!/bin/bash
case "$*" in
  "-4 route get "*) echo "$4 via ${ROUTE_VIA:-192.0.2.254} dev eth0 src 192.0.2.50 uid 0" ;;
  "-4 route show default") echo "default via ${DEFAULT_VIA:-192.0.2.254} dev eth0 proto static" ;;
  *) exit 1 ;;
esac
EOF
cat > "$t/bin/ssh" <<EOF
#!/bin/bash
cmd="\${*: -1}"
echo "ssh \${*: -2}" >> $t/calls
case \$cmd in
  true) exit 0 ;;
  *backup.pem.keyid) echo keyid-\${2:-x}; exit 0 ;;
  *backup.pem) printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'AAAA' '-----END PRIVATE KEY-----' '-----BEGIN CERTIFICATE-----' 'BBBB' '-----END CERTIFICATE-----'; exit 0 ;;
  *seal-1.key) cat $t/node.key; exit 0 ;;
esac
exit 1
EOF
cat > "$t/libexec/sops" <<'EOF'
#!/usr/bin/env python3
import base64, json, sys
a = sys.argv[1:]
out, src = a[a.index("--output") + 1], a[-1]
open(out, "wb").write(base64.b64decode(json.load(open(src))["data"]))
EOF
for job in opnsense-backup opnsense-offbox secrets-bundle secrets-bundle-offbox; do
  printf '#!/bin/bash\necho "job %s" >> %s/calls\n' "$job" "$t" > "$t/libexec/$job.sh"
done
cat > "$venv/ansible-inventory" <<'EOF'
#!/usr/bin/env python3
import json, os, sys, yaml
d = yaml.safe_load(open(os.path.join(sys.argv[sys.argv.index("-i") + 1], "hosts.yml")))
out, hv = {}, {}
def walk(name, g, inherited):
    g = g or {}
    vars_ = dict(inherited); vars_.update(g.get("vars") or {})
    hosts = []
    for h, v in (g.get("hosts") or {}).items():
        merged = dict(vars_); merged.update(hv.get(h, {})); merged.update(v or {}); hv[h] = merged; hosts.append(h)
    out[name] = {"hosts": hosts, "children": list((g.get("children") or {}).keys())}
    for c, cg in (g.get("children") or {}).items(): walk(c, cg, vars_)
walk("all", d.get("all"), {})
out["_meta"] = {"hostvars": hv}
print(json.dumps(out))
EOF
cat > "$venv/ansible-playbook" <<EOF
#!/bin/bash
echo "playbook \$*" >> $t/calls
cp "\${2%/}/hosts.yml" $t/seen-inventory.yml
if [[ "\$*" == *"--tags drill"* && -z "\${DRILL_NOSNAP:-}" ]]; then
  echo '    "2026-11-18T03:00:30Z PASS: volume restore test, 4 folders, 1 database dumps, snapshot 36fe4321 of 2026-11-18T03:00:26",'
  echo '    "2026-11-18T03:00:20Z PASS: etcd restore test, revision 202, 201 keys under /, key /registry/namespaces/kube-system present, snapshot c5523412 of 2026-11-18T03:00:17"'
elif [[ "\$*" == *"--tags drill"* ]]; then
  echo '    "2026-11-18T03:00:30Z PASS: no volume backups recorded on node; nothing to test",'
fi
exit \${DRILL_RC:-0}
EOF
chmod +x "$t/bin/"* "$t/libexec/"*.sh "$t/libexec/sops" "$venv/ansible-inventory" "$venv/ansible-playbook"
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^work=.*|work=$t/work|" \
    -e "s|PATH=\$libexec/ansible-venv/bin:/usr/local/bin|PATH=\$libexec/ansible-venv/bin:$t/bin:/usr/local/bin|" \
    -e "s|/dev/shm/rebuild-prod-seal.XXXXXX|/dev/shm/rebuild-prod-seal.test-XXXXXX|" \
    hosts/ansible/roles/agent_box/files/rebuild-prod.sh > "$t/run/rebuild-prod.sh"
grep -q "^keys=$t/keys" "$t/run/rebuild-prod.sh" && grep -q "^work=$t/work" "$t/run/rebuild-prod.sh" &&
  grep -q ":$t/bin:" "$t/run/rebuild-prod.sh" || { echo "FAIL the test could not point the wrapper at its folders"; exit 1; }

run() { : > "$t/calls"; bash "$t/run/rebuild-prod.sh" "$@" > "$t/out" 2>&1; rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls"); }
full_stages() { for st in vms cluster storage restore gitops secrets apps gateway checks; do printf '%s\n' "2026-11-18T03:00:00Z $st start" "2026-11-18T03:00:01Z $st end rc=0 1s"; done; }
ld=$t/work/rebuild-dev/logs
# dev_log: the dev folder holds this one run (03:00). dev_log_teardown: a teardown-only run, alone or after another run
# (the log of `rebuild.sh teardown`: the same ending line, but only the teardown stage ran).
dev_log() { rm -f "$ld"/*; { printf '%s\n' "rebuild: central-hub $1"; full_stages; printf '%s\n' "$2"; } > "$ld/rebuild-20261118T030000Z.log"; }
dev_log_teardown() { printf '%s\n' "rebuild: central-hub $1" "2026-11-18T0${2:-3}:00:00Z teardown start" "2026-11-18T0${2:-3}:00:20Z teardown end rc=0 20s" \
  "rebuild: all stages passed" > "$ld/rebuild-20261118T0${2:-3}0000Z.log"; }
dev_log_later() { { printf '%s\n' "rebuild: central-hub $1"; full_stages; printf '%s\n' "$3"; } > "$ld/rebuild-20261118T0${2}0000Z.log"; }
destroy() { python3 -c 'import json, sys; print(json.dumps({"resource_changes": [
  {"type": "proxmox_virtual_environment_vm", "address": "a%d" % i, "change": {"actions": ["delete"], "before": {"vm_id": i}}}
  for i in map(int, sys.argv[1:])]}))' "$@" > "$t/destroy.json"; }
inventory() { printf '%s\n' "all:" "  children:" "    proxmox:" "      hosts:" "        pve-a: {ansible_host: 192.0.2.1}" \
  "    k8s_nodes:" "      vars:" "        ansible_user: almalinux" "        ansible_ssh_common_args: -o ProxyJump=root@192.0.2.1" \
  "        ansible_ssh_private_key_file: /Users/someone/.ssh/id" "        k8s_gitops_cluster_labels: {env: prod}" \
  "        k8s_backup_enabled: true" "        k8s_backup_azure_identity: true" "        k8s_backup_env_file: /Users/someone/.config/central-hub/c1-backup.env" \
  "        k8s_identity_values_file: /Users/someone/.config/central-hub/identity.env" "$@" \
  "      children:" "        k8s_control_plane:" "          hosts:" "            cp-a: {ansible_host: 192.0.2.10}" \
  "        k8s_workers:" "          hosts:" "            wk-a: {ansible_host: 192.0.2.11}" > "$t/keys/prod/inventory-hosts.yml"; }
seal_copy() { python3 -c 'import base64, json, sys; print(json.dumps({"data": base64.b64encode(open(sys.argv[1], "rb").read()).decode()}))' \
  "$1" > "$t/keys/prod/openbao-seal.key.sops.json"; }

# 1
r1=""
for args in "" "apply" "rebuild" "rebuild notatap" "rebuild cmsg_short" "check extra" "rebuild cmsg_01ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
            "rebuild cmsg_01ABCDEFGHIJKLMNOPQRSTUVWXYZ main" "rebuild cmsg_01ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123"; do
  # shellcheck disable=SC2086
  run $args; r1+="$rc:${calls:-none} "
done
if [[ $r1 == "2:none 2:none 2:none 2:none 2:none 2:none 2:none 2:none 2:none " ]]; then ok "1. usage errors (rebuild with no commit, or one that is not 7 to 40 hex digits, too), nothing run"; else bad "1. $r1"; fi

# 2
run check
if [[ $rc -eq 1 && $out == *"FAIL: rebuild-prod: missing: "*"proxmox-lab.env"*"k8s.tfvars"*"home-k8s.tfstate"* &&
      $out == *"nothing was changed"* && $calls != *playbook* && $calls != *one-command* ]]; then
  ok "2. check names the missing files and changes nothing"
else bad "2. $rc $out"; fi

# Everything in place.
printf '%s\n' 'PROXMOX_VE_ENDPOINT=https://pve.invalid:8006/' 'PROXMOX_VE_API_TOKEN=agentlab@pve!lab=x' > "$t/keys/proxmox-lab.env"
printf '%s\n' 'node_ssh_public_key = "ssh-ed25519 AAAAmac mac"' 'nodes = {' \
  '  cp-a = { vm_id = 200, role = "control-plane", address = "192.0.2.10" }' \
  '  wk-a = { vm_id = 201, role = "worker", address = "192.0.2.11" }' '}' > "$t/keys/prod/tfvars/k8s.tfvars"
echo '{"resources": []}' > "$t/keys/prod/state/home-k8s.tfstate"
ssh-keygen -q -t ed25519 -N '' -C test -f "$t/keys/prod-node-key"
for f in prod/c1-secrets-encryption.key c1-backup.env prod/identity.env prod/secret-source.env prod/cloudflare-dns01-token.txt \
         secrets-bundle/age-identity.txt; do echo x > "$t/keys/$f"; done
printf 'K%.0s' {1..32} > "$t/node.key"; seal_copy "$t/node.key"
echo '{"seal_node": "wk-a", "store_host": "bao.invalid", "box_cidr": "192.0.2.50/32", "admin_address": "192.0.2.60"}' > "$t/work/openbao-prod.json"
inventory; destroy 200 201; dev_log "$sha" "rebuild: all stages passed"

# 3, 4
run check
seen=$(python3 -c 'import json, sys, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$t/work/rebuild-prod/inventory/hosts.yml" 2>/dev/null)
if [[ $rc -eq 0 && $out == *"every check passed; nothing was changed"* && $out == *"no changes with the Mac's tfvars"* &&
      $out == *"destroys only VMs 200 201"* && $out == *"reaches all 2 prod nodes"* && $out == *"routes do not go through a prod node: Proxmox API next hop 192.0.2.254, default via 192.0.2.254"* && $out == *"dev passed every stage at ${sha:0:12}"* &&
      $out != *FAIL* && $calls != *playbook* && $calls != *one-command* && $calls != *job* ]]; then
  ok "3. check passes every line and changes nothing"
else bad "3. $rc $out"; fi
v=$(python3 -c 'import json, sys; d = json.loads(sys.argv[1]); v = d["all"]["children"]["k8s_nodes"]["vars"]; k = sys.argv[2]
print(v["ansible_ssh_private_key_file"] == k + "/prod-node-key", v["k8s_backup_env_file"] == k + "/c1-backup.env",
      v["k8s_identity_values_file"] == k + "/prod/identity.env", v["k8s_backup_restore_own_env"], v["k8s_backup_restore_source_host"],
      v["k8s_gitops_source_local_path_stable_folders"], v["k8s_backup_azure_seed_dir"] == k + "/prod/backup-certs",
      v["k8s_gitops_source_openbao_seal_node"], "proxmox" in d["all"]["children"], v["k8s_backup_restore_check_identity"],
      v["k8s_gitops_source_openbao_admin_address"])' "$seen" "$t/keys" 2>/dev/null)
if [[ $v == "True True True True wk-a True True wk-a False False 192.0.2.60" && $seen != *ProxyJump* && $seen != */Users/* ]] &&
   grep -q "^node_ssh_public_key = \"$(cut -d' ' -f1-2 < "$t/keys/prod-node-key.pub")" "$t/work/rebuild-prod/k8s.tfvars"; then
  ok "4. the box's copies: its key, the box's files, prod's own restore, stable folders, the carried certificates"
else bad "4. [$v]"; fi

# 5
r5=""
TOFU_PLAN_RC=2 run check; [[ $rc -eq 1 && $out == *"plans changes with the Mac's tfvars"* ]] && r5+="a"
destroy 200 201 258; run check; [[ $rc -eq 1 && $out == *"other than prod's node VMs: VM 258"* ]] && r5+="b"; destroy 200 201
inventory "        k8s_certs_smoke_root_file: /Users/someone/.config/central-hub/lab-ca/root.crt"
run check; [[ $rc -eq 1 && $out == *"k8s_certs_smoke_root_file still points at the Mac"* ]] && r5+="c"; inventory
dev_log 1111111111111111111111111111111111111111 "rebuild: all stages passed"
run check; [[ $rc -eq 1 && $out == *"ran another commit"* ]] && r5+="d"
dev_log "$sha" "rebuild: stage apps failed"; run check; [[ $rc -eq 1 && $out == *"did not pass every stage"* ]] && r5+="e"
rm -f "$ld"/*; dev_log_teardown "$sha"; run check; [[ $rc -eq 1 && $out == *"no dev run other than a teardown is logged"* ]] && r5+="i"
dev_log "$sha" "rebuild: all stages passed"; dev_log_teardown "$sha" 4; run check
[[ $rc -eq 0 && $out == *"dev passed every stage at ${sha:0:12} (run rebuild-20261118T030000Z.log)"* ]] && r5+="j"
dev_log "$sha" "rebuild: all stages passed"; dev_log_later "$sha" 4 "rebuild: stage apps failed"; dev_log_teardown "$sha" 5; run check
[[ $rc -eq 1 && $out == *"the newest dev run (rebuild-20261118T040000Z.log) did not pass every stage"* ]] && r5+="k"
dev_log "$sha" "rebuild: all stages passed"
sed -i 's/vm_id = 201/vm_id = 301/' "$t/keys/prod/tfvars/k8s.tfvars"
run check; [[ $rc -eq 1 && $out == *"outside 200-249: 301"* ]] && r5+="f"
sed -i 's/vm_id = 301/vm_id = 201/' "$t/keys/prod/tfvars/k8s.tfvars"
ROUTE_VIA=192.0.2.11 run check; [[ $rc -eq 1 && $out == *"route goes through a prod node"* ]] && r5+="g"
DEFAULT_VIA=192.0.2.10 run check; [[ $rc -eq 1 && $out == *"route goes through a prod node"*"default via 192.0.2.10"* ]] && r5+="h"
if [[ $r5 == abcdeijkfgh ]]; then ok "5. check passes a teardown after a full pass, and refuses a plan with changes, VM 258, a Mac path, another dev commit, a failed dev run, a teardown-only dev run alone, VM 301, a route through a node"
else bad "5. [$r5] $out"; fi

# 6
tap=cmsg_01ABCDEFGHIJKLMNOPQRSTUVWXYZ
run rebuild "$tap" "${sha:0:12}"
order=$(grep -oE '^(playbook [^ ]+ [^ ]+ [^ ]+|ssh [^ ]+ .*(backup.pem|seal-1.key)$|job [a-z-]+|one-command .*|seal-in-memory [0-9]+)' "$t/calls" |
  sed -E 's/^playbook -i [^ ]+ /playbook /; s/^ssh [^ ]+ (sudo -n )?cat .*\/(backup.pem|seal-1.key)$/ssh \2/' | uniq | tr '\n' '|')
want="playbook playbooks/k8s-backup.yml|ssh backup.pem|ssh seal-1.key|job opnsense-backup|job opnsense-offbox|job secrets-bundle|job secrets-bundle-offbox|one-command $t/work/rebuild-prod --teardown|seal-in-memory 32|"
stages=$(sed -n 's/^STAGES=//p' "$t/seen-rebuild.env")
if [[ $rc -eq 0 && $order == "$want" && $calls == *"playbooks/k8s-backup.yml --tags drill -e k8s_backup_drill=true"* &&
      -s $t/keys/prod/backup-certs/wk-a.pem && -s $t/keys/prod/backup-certs/cp-a.pem.keyid &&
      $(stat -c %a "$t/keys/prod/backup-certs/wk-a.pem") == 600 && $out != *"BEGIN PRIVATE KEY"* && $out != *KKKK* &&
      $stages == '"vms cluster storage openbao-seal restore gitops secrets apps gateway certs identity identity-db ui backup checks"' &&
      $(cat "$t/seen-rebuild.env") == *"ENV_NAME=prod"* && $(cat "$t/seen-rebuild.env") == *"TEARDOWN_TARGET=proxmox_virtual_environment_vm.node"* &&
      $(grep -c 'plan .*-destroy -target=proxmox_virtual_environment_vm.node ' "$t/calls") -ge 1 && $(cat "$t/seen-rebuild.env") == *"TOFU_ENV=$t/keys/proxmox-lab.env"* &&
      $(cat "$t/seen-rebuild.env") == *"k8s-restore.yml -e k8s_backup_enabled=false"* && -e $t/work/state/prod-stable-folders &&
      $out == *"owner tap $tap"* && $out == *"restore test passed: volume restore test, 4 folders, 1 database dumps, snapshot 36fe4321"*"etcd restore test"*"snapshot c5523412"* && $out == *"PASS: rebuild-prod: prod torn down and built again"* &&
      -z $(ls -d /dev/shm/rebuild-prod-seal.test-* 2>/dev/null) ]]; then
  ok "6. rebuild: the checks before a teardown in order, the certificates kept, then the one command with prod's stages"
else bad "6. $rc [$order] [$stages] $out"; fi

# 7
printf 'J%.0s' {1..32} > "$t/node.key"; run rebuild "$tap" "$sha"; r7a=$rc o7a=$out c7a=$calls
printf 'K%.0s' {1..32} > "$t/node.key"; DRILL_RC=2 run rebuild "$tap" "$sha"; r7b=$rc o7b=$out c7b=$calls
DRILL_NOSNAP=1 run rebuild "$tap" "$sha"; r7c=$rc o7c=$out c7c=$calls
if [[ $r7a -eq 1 && $o7a == *"differs from the seal node's key"* && $c7a != *one-command* && $c7a != *job* &&
      $r7b -eq 1 && $o7b == *"backup and restore test before the teardown failed"* && $c7b != *one-command* && $c7b != *"ssh "*backup.pem* &&
      $r7c -eq 1 && $o7c == *"named no tested volume snapshot"* && $c7c != *one-command* && $c7c != *"ssh "*backup.pem* ]]; then
  ok "7. a differing seal key, a failed backup test, or a drill that names no tested snapshot destroys nothing"
else bad "7. $r7a $o7a | $r7b $o7b | $r7c $o7c"; fi

# 8
run log
if [[ $rc -eq 0 && $out == *"rebuild-prod: rebuild at central-hub ${sha:0:12}, owner tap $tap"* ]]; then ok "8. log prints the run's lines"
else bad "8. $rc $out"; fi

# 9. The Mac's inventory leaves the labels to the k8s_gitops role's default (env prod) and names its sign-in CA on the Mac.
inventory "        k8s_gitops_sso_root_ca_file: /Users/someone/.config/central-hub/lab-ca/root.crt"
sed -i '/k8s_gitops_cluster_labels/d' "$t/keys/prod/inventory-hosts.yml"
run check; o9a=$out
mkdir -p "$t/keys/prod/lab-ca"; echo x > "$t/keys/prod/lab-ca/root.crt"
run check; o9b=$out
box=$(python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); v = d["all"]["children"]["k8s_nodes"]["vars"]; l = v["k8s_gitops_cluster_labels"]; print(l["env"], l["place"], l["purpose"], v["k8s_gitops_sso_root_ca_file"])' "$t/work/rebuild-prod/inventory/hosts.yml" 2>&1)
inventory "        k8s_gitops_cluster_labels: {env: dev}"
run check; o9c=$out
if [[ $o9a == *"k8s_gitops_sso_root_ca_file is $t/keys/prod/lab-ca/root.crt, which is not on the box"* && $o9a != *"labelled env"* && $o9a != *"still points at the Mac"* &&
      $o9b == *"every private file at the box's copy"* && $o9b != *"labelled env"* && $box == "prod home apps $t/keys/prod/lab-ca/root.crt" &&
      $o9c == *"is labelled env dev, not prod"* ]]; then
  ok "9. no labels in the Mac's inventory: the box's copy gets the role's default (env prod); an env other than prod is still refused; the sign-in CA is mapped"
else bad "9. [$box] $o9a | $o9b | $o9c"; fi

# 10. The sign-in theme folder: the box's copy keeps the folder's own name under prod/identity-theme/, where the
# controller's prod-files run puts it, and check refuses one with no login/theme.properties before any teardown.
inventory "        k8s_identity_theme_dir: /Users/someone/src/brand-theme/"
run check; o10a=$out
mkdir -p "$t/keys/prod/identity-theme/brand-theme/login"
run check; o10b=$out
echo 'parent=keycloak' > "$t/keys/prod/identity-theme/brand-theme/login/theme.properties"
run check; o10c=$out r10c=$rc
th=$(python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["all"]["children"]["k8s_nodes"]["vars"]["k8s_identity_theme_dir"])' "$t/work/rebuild-prod/inventory/hosts.yml" 2>&1)
if [[ $o10a == *"k8s_identity_theme_dir is $t/keys/prod/identity-theme/brand-theme, which is not on the box"* &&
      $o10b == *"k8s_identity_theme_dir is $t/keys/prod/identity-theme/brand-theme, which has no login/theme.properties"* &&
      $r10c -eq 0 && $o10c != *FAIL* && $th == "$t/keys/prod/identity-theme/brand-theme" ]]; then
  ok "10. the theme folder keeps its name under prod/identity-theme/, and one with no login/theme.properties is refused"
else bad "10. [$th] $o10a | $o10b | $r10c $o10c"; fi
# 11. rebuild builds the commit the go names, never main's newest, and only a commit on main.
inventory; rm -f "$t/gitcalls"; run check; g11a=$(cat "$t/gitcalls" 2>/dev/null)
rm -f "$t/gitcalls"; run rebuild "$tap" "${sha:0:12}"; r11b=$rc g11b=$(cat "$t/gitcalls" 2>/dev/null)
NOT_ON_MAIN=1 run rebuild "$tap" "$sha"; r11c=$rc o11c=$out c11c=$calls
run rebuild "$tap" fedcba9; r11d=$rc o11d=$out c11d=$calls
if [[ $g11a == "git origin/main" && $r11b -eq 0 && $g11b == "git $sha" &&
      $r11c -eq 1 && $o11c == *"commit $sha is not on main"* && -z $c11c &&
      $r11d -eq 1 && $o11d == *"commit fedcba9 is not in the box's checkout of main"* && -z $c11d ]]; then
  ok "11. rebuild checks out the commit the go names (check, main's newest); a commit not on main, or unknown, runs nothing"
else bad "11. [$g11a] $r11b [$g11b] | $r11c $o11c [$c11c] | $r11d $o11d [$c11d]"; fi
# 12. The backup target: the Proxmox host over sftp is refused before anything is destroyed when the box's copy has no host
# address for the nodes' alias (the carried keys need it); with no Azure sign-in there is no certificate to carry, and the rebuild goes on without one.
inventory "        k8s_backup_sftp: true"
sed -i '/k8s_backup_azure_identity/d' "$t/keys/prod/inventory-hosts.yml"
dev_log "$sha" "rebuild: all stages passed"
run check; r12a=$rc o12a=$out
run rebuild "$tap" "$sha"; r12b=$rc c12b=$calls
inventory; sed -i '/k8s_backup_azure_identity/d' "$t/keys/prod/inventory-hosts.yml"
rm -rf "$t/keys/prod/backup-certs"
mkdir -p "$t/keys/prod/backup-sftp"; echo carried > "$t/keys/prod/backup-sftp/n.key"
run rebuild "$tap" "$sha"; r12c=$rc o12c=$out c12c=$calls
if [[ $r12a -eq 1 && $o12a == *"k8s_backup_sftp is true but the box's copy has no host address for node"* &&
      $r12b -eq 1 && $c12b != *playbook* && $c12b != *one-command* &&
      $r12c -eq 0 && $o12c == *"no Azure sign-in on the prod nodes (k8s_backup_azure_identity off), so no backup certificate to carry"* &&
      $c12c != *backup.pem* && $c12c == *one-command* && ! -e $t/keys/prod/backup-certs &&
      $o12c == *"the carried sftp keys were deleted from the box"* && ! -e $t/keys/prod/backup-sftp ]]; then
  ok "12. the Proxmox host as backup target with no host address is refused before anything runs; no Azure sign-in: no certificate carried"
else bad "12. $r12a $o12a | $r12b [$c12b] | $r12c $o12c"; fi

# 12c. A plan with changes names what it changes by type, name and VM ID, never by address: a node's address carries its private
# hostname as the index. The stand-in `tofu show` gives a node resource keyed by a fake hostname; the output must not hold it.
cat > "$t/plan-changes.json" <<'J'
{"resource_changes":[{"address":"proxmox_virtual_environment_vm.node[\"fakehost-zq.example.invalid\"]","type":"proxmox_virtual_environment_vm","name":"node","index":"fakehost-zq.example.invalid","change":{"actions":["update"],"before":{"vm_id":200,"memory":4096},"after":{"vm_id":200,"memory":8192}}},
{"address":"proxmox_download_file.almalinux10[0]","previous_address":"proxmox_download_file.almalinux10","type":"proxmox_download_file","name":"almalinux10","change":{"actions":["no-op"],"before":{"file_name":"x"},"after":{"file_name":"x"}}}]}
J
inventory "        k8s_backup_azure_identity: true"
dev_log "$sha" "rebuild: all stages passed"
TOFU_PLAN_RC=2 TOFU_SHOW_FILE="$t/plan-changes.json" run check; r12c2=$rc o12c2=$out
if [[ $o12c2 == *"plan: proxmox_virtual_environment_vm.node vm_id 200 update; differs in: memory"* && $o12c2 == *"plan: proxmox_download_file.almalinux10 moved in the state"* && $o12c2 != *fakehost-zq* ]]; then
  ok "12c. a plan with changes is named by type, name and VM ID, and a node's hostname never appears"
else bad "12c. $r12c2 $o12c2"; fi

# 12d. A plan whose only changes are moves in the state (the code's moved blocks, the state older than the code) passes the plan
# check, naming the count; a real change next to a move still fails (12c).
cat > "$t/plan-moves.json" <<'J'
{"resource_changes":[{"address":"proxmox_download_file.almalinux10[0]","previous_address":"proxmox_download_file.almalinux10","type":"proxmox_download_file","name":"almalinux10","change":{"actions":["no-op"],"before":{"file_name":"x"},"after":{"file_name":"x"}}},
{"address":"proxmox_virtual_environment_vm.template[0]","previous_address":"proxmox_virtual_environment_vm.template","type":"proxmox_virtual_environment_vm","name":"template","change":{"actions":["no-op"],"before":{"vm_id":9000},"after":{"vm_id":9000}}}]}
J
TOFU_PLAN_RC=2 TOFU_SHOW_FILE="$t/plan-moves.json" run check; o12d=$out
if [[ $o12d == *"PASS: rebuild-prod: OpenTofu: the only plan changes are state moves (nothing changes on the host): 2 resource(s)"* && $o12d != *"plans changes with the Mac"* ]]; then
  ok "12d. a plan of state moves only passes, naming the count"
else bad "12d. $o12d"; fi

# 12e. A targeted destroy refuses a state that still holds moved resources ("Moved resource instances excluded by targeting"), so the
# check plans the teardown on a COPY of the state after a refresh-only apply, never on the live state, then points back at the live
# state; a refresh-only apply that fails fails the check and no destroy is planned.
: > "$t/calls"
run check; o12e=$out
seq12e=$(grep -E '^tofu (init .*path=|apply -refresh-only|plan .*-destroy -target)' "$t/calls" | sed -E 's/^tofu init .*state-moves-settled.*/init-copy/; s/^tofu init .*home-k8s.tfstate.*/init-live/; s/^tofu apply -refresh-only.*/refresh-only/; s/^tofu plan .*-destroy -target=([^ ]+).*/destroy-plan \1/' | tr '\n' '|')
if [[ $seq12e == *"init-live|init-copy|refresh-only|destroy-plan proxmox_virtual_environment_vm.node|init-live|"* && $(find "$t" -name 'state-moves-settled*' | wc -l) == 0 ]]; then
  ok "12e. the teardown is planned on a copy of the state after a refresh-only apply, and the live state is pointed at again"
else bad "12e. [$seq12e] $o12e"; fi
: > "$t/calls"
TOFU_APPLY_RC=1 run check; o12f=$out
if [[ $o12f == *"FAIL: rebuild-prod: OpenTofu could not plan the teardown (rc 1)"* && $(grep -c -- '-destroy' "$t/calls") == 0 ]]; then
  ok "12f. a failed refresh-only apply fails the check and plans no destroy"
else bad "12f. $o12f"; fi

# 12g. A failed OpenTofu step prints fixed facts only (the output's line count and which phrases of a closed list it holds), never a
# line of its own text. Each case carries a value that a mask would miss, or the token itself, and none may reach the output.
leak_case() { # <label> <text> <secret...>: the secrets must not appear, the fixed facts must
  local label=$1 text=$2 sec o good=1; shift 2
  TOFU_INIT_RC=1 TOFU_INIT_TEXT=$text run check; o=$out
  [[ $o == *"FAIL: rebuild-prod: OpenTofu init failed: "*"output line(s); phrases found: "* ]] || good=0
  for sec in "$@"; do [[ $o != *"$sec"* ]] || good=0; done
  if (( good )); then ok "12g. $label: only fixed facts are printed, no secret"; else bad "12g. $label: $o"; fi
}
leak_case "a broken env-file line holding the token" $'/keys/proxmox-lab.env: line 2: PVEAPIToken=tok-SECRET-1234: command not found' SECRET PVEAPIToken tok-
leak_case "a one-dot hostname" $'dial failed for pve.invalid 192.0.2.10' pve.invalid 192.0.2.10
leak_case "a dotless hostname" $'Error: cannot reach pvehost-private on 8006' pvehost-private
leak_case "an IPv6 address" $'Failed to query 2001:db8::10 refused' 2001:db8
TOFU_INIT_RC=1 TOFU_INIT_TEXT=$'one\nregistry thing\nPermission denied here' run check; o12h=$out
if [[ $o12h == *"OpenTofu init failed: 3 output line(s); phrases found: Permission denied,registry"* ]]; then
  ok "12h. the closed list names the phrases found, comma-separated, with the line count"
else bad "12h. $o12h"; fi

# 12b. The wrapper's PATH reaches `ip` (/usr/sbin on the box, where the route check reads the routing table): on the box the check
# failed with "no route to the Proxmox API's address" because `ip` was not found.
if grep -qE '^export HOME=.* PATH=[^ ]*:/usr/sbin(:|$)' hosts/ansible/roles/agent_box/files/rebuild-prod.sh; then ok "12b. the wrapper's PATH includes /usr/sbin, so the route check finds ip"; else bad "12b. PATH lacks /usr/sbin"; fi

# 13. The floor: rebuild asks whether PIN_FLOOR is an ancestor of the pinned commit, and refuses below it before anything runs;
# check (no commit) never asks.
floor=$(sed -n 's/^PIN_FLOOR=\([0-9a-f]\{40\}\)$/\1/p' hosts/ansible/roles/agent_box/files/rebuild-prod.sh)
inventory; rm -f "$t/floorcalls"; run check; f13a=$(cat "$t/floorcalls" 2>/dev/null)
rm -f "$t/floorcalls"; run rebuild "$tap" "$sha"; r13b=$rc f13b=$(cat "$t/floorcalls" 2>/dev/null)
rm -f "$t/gitcalls"; BELOW_FLOOR=1 run rebuild "$tap" "$sha"; r13c=$rc o13c=$out c13c=$calls g13c=$(cat "$t/gitcalls" 2>/dev/null)
if [[ -n $floor && -z $f13a && $r13b -eq 0 && $f13b == "floor $floor $sha" &&
      $r13c -eq 1 && $o13c == *"commit $sha is older than the floor ${floor:0:7}"* && -z $c13c && -z $g13c ]]; then
  ok "13. a commit below the floor is refused before any checkout or run; at or above it the rebuild goes on; check never asks"
else bad "13. [$floor] [$f13a] $r13b [$f13b] | $r13c $o13c [$c13c] [$g13c]"; fi

exit "$fail"
