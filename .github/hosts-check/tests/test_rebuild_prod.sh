#!/usr/bin/env bash
# The rebuild-prod wrapper's own checks (hosts/ansible/roles/agent_box/files/rebuild-prod.sh), with stand-ins for git,
# tofu, ssh, sops, ansible-inventory, ansible-playbook, the box's off-box jobs and hosts/rebuild-k8s.sh:
#   1. Usage: no action, another action, rebuild with no tap id or a malformed one: usage errors, nothing run.
#   2. check with nothing on the box names what is missing and changes nothing.
#   3. check with everything in place passes every line: the box's state is the live prod, the teardown destroys
#      only VMs 200 and 201, every node answers, the box routes around the nodes, and dev passed at this commit.
#   4. The box's inventory copy: the box's key and plain ssh, the private files at the box's copies, the rebuild's
#      own settings (prod's own restore, stable folders, the carried certificates), no proxmox group.
#   5. check refuses, each alone: a plan with changes, a teardown that would destroy VM 258, a value still on the
#      Mac, a dev run at another commit, a failed dev run, a node VM ID outside 200-249, the box's route to the
#      Proxmox API or its default route through a prod node.
#   6. rebuild runs the checks before a teardown in order (backup and restore test, the certificates, the seal
#      key, the firewall copy, the bundle), keeps each node's certificate, then the one command with prod's stages,
#      the seal key in memory, and the tap id in the log.
#   7. rebuild with a seal key that differs from the node's, a failed backup test, or a drill whose restore tests
#      name no snapshot (a node with nothing to test), destroys nothing.
#   8. log prints the run's lines.
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
  clone*) d="\${@: -1}"; mkdir -p "\$d/.git" "\$d/hosts/ansible" "\$d/hosts/terraform/home/k8s"
          printf '%s\n' '#!/bin/bash' 'echo "one-command \$*" >> $t/calls' 'cp "\$1/rebuild.env" $t/seen-rebuild.env' \
            'f=\$(sed -n "s/^OPENBAO_SEAL_KEY_FILE=//p" "\$1/rebuild.env"); [ -s "\$f" ] && echo "seal-in-memory \$(wc -c < "\$f")" >> $t/calls' \
            'exit \${ONE_RC:-0}' > "\$d/hosts/rebuild-k8s.sh" ;;
  *rev-parse*) echo $sha ;;
esac
exit 0
EOF
cat > "$t/bin/tofu" <<EOF
#!/bin/bash
echo "tofu \${*:2}" >> $t/calls
case " \$* " in
  *" init "*) exit 0 ;;
  *" show "*) cat $t/destroy.json; exit 0 ;;
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
dev_log() { printf '%s\n' "rebuild: central-hub $1" "2026-11-18T03:00:00Z vms start" "$2" > "$t/work/rebuild-dev/logs/rebuild-20261118T030000Z.log"; }
destroy() { python3 -c 'import json, sys; print(json.dumps({"resource_changes": [
  {"type": "proxmox_virtual_environment_vm", "address": "a%d" % i, "change": {"actions": ["delete"], "before": {"vm_id": i}}}
  for i in map(int, sys.argv[1:])]}))' "$@" > "$t/destroy.json"; }
inventory() { printf '%s\n' "all:" "  children:" "    proxmox:" "      hosts:" "        pve-a: {ansible_host: 192.0.2.1}" \
  "    k8s_nodes:" "      vars:" "        ansible_user: almalinux" "        ansible_ssh_common_args: -o ProxyJump=root@192.0.2.1" \
  "        ansible_ssh_private_key_file: /Users/someone/.ssh/id" "        k8s_gitops_cluster_labels: {env: prod}" \
  "        k8s_backup_enabled: true" "        k8s_backup_env_file: /Users/someone/.config/central-hub/c1-backup.env" \
  "        k8s_identity_values_file: /Users/someone/.config/central-hub/identity.env" "$@" \
  "      children:" "        k8s_control_plane:" "          hosts:" "            cp-a: {ansible_host: 192.0.2.10}" \
  "        k8s_workers:" "          hosts:" "            wk-a: {ansible_host: 192.0.2.11}" > "$t/keys/prod/inventory-hosts.yml"; }
seal_copy() { python3 -c 'import base64, json, sys; print(json.dumps({"data": base64.b64encode(open(sys.argv[1], "rb").read()).decode()}))' \
  "$1" > "$t/keys/prod/openbao-seal.key.sops.json"; }

# 1
r1=""
for args in "" "apply" "rebuild" "rebuild notatap" "rebuild cmsg_short" "check extra"; do
  # shellcheck disable=SC2086
  run $args; r1+="$rc:${calls:-none} "
done
if [[ $r1 == "2:none 2:none 2:none 2:none 2:none 2:none " ]]; then ok "1. usage errors, nothing run"; else bad "1. $r1"; fi

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
echo '{"seal_node": "wk-a", "store_host": "bao.invalid"}' > "$t/work/openbao-prod.json"
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
      v["k8s_gitops_source_openbao_seal_node"], "proxmox" in d["all"]["children"], v["k8s_backup_restore_check_identity"])' "$seen" "$t/keys" 2>/dev/null)
if [[ $v == "True True True True wk-a True True wk-a False False" && $seen != *ProxyJump* && $seen != */Users/* ]] &&
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
dev_log "$sha" "rebuild: all stages passed"
sed -i 's/vm_id = 201/vm_id = 301/' "$t/keys/prod/tfvars/k8s.tfvars"
run check; [[ $rc -eq 1 && $out == *"outside 200-249: 301"* ]] && r5+="f"
sed -i 's/vm_id = 301/vm_id = 201/' "$t/keys/prod/tfvars/k8s.tfvars"
ROUTE_VIA=192.0.2.11 run check; [[ $rc -eq 1 && $out == *"route goes through a prod node"* ]] && r5+="g"
DEFAULT_VIA=192.0.2.10 run check; [[ $rc -eq 1 && $out == *"route goes through a prod node"*"default via 192.0.2.10"* ]] && r5+="h"
if [[ $r5 == abcdefgh ]]; then ok "5. check refuses a plan with changes, VM 258, a Mac path, another dev commit, a failed dev run, VM 301, a route through a node"
else bad "5. [$r5] $out"; fi

# 6
tap=cmsg_01ABCDEFGHIJKLMNOPQRSTUVWXYZ
run rebuild "$tap"
order=$(grep -oE '^(playbook [^ ]+ [^ ]+ [^ ]+|ssh [^ ]+ .*(backup.pem|seal-1.key)$|job [a-z-]+|one-command .*|seal-in-memory [0-9]+)' "$t/calls" |
  sed -E 's/^playbook -i [^ ]+ /playbook /; s/^ssh [^ ]+ (sudo -n )?cat .*\/(backup.pem|seal-1.key)$/ssh \2/' | uniq | tr '\n' '|')
want="playbook playbooks/k8s-backup.yml|ssh backup.pem|ssh seal-1.key|job opnsense-backup|job opnsense-offbox|job secrets-bundle|job secrets-bundle-offbox|one-command $t/work/rebuild-prod --teardown|seal-in-memory 32|"
stages=$(sed -n 's/^STAGES=//p' "$t/seen-rebuild.env")
if [[ $rc -eq 0 && $order == "$want" && $calls == *"playbooks/k8s-backup.yml --tags drill -e k8s_backup_drill=true"* &&
      -s $t/keys/prod/backup-certs/wk-a.pem && -s $t/keys/prod/backup-certs/cp-a.pem.keyid &&
      $(stat -c %a "$t/keys/prod/backup-certs/wk-a.pem") == 600 && $out != *"BEGIN PRIVATE KEY"* && $out != *KKKK* &&
      $stages == '"vms cluster storage openbao-seal restore gitops secrets apps gateway certs identity identity-db ui backup checks"' &&
      $(cat "$t/seen-rebuild.env") == *"ENV_NAME=prod"* && $(cat "$t/seen-rebuild.env") == *"TOFU_ENV=$t/keys/proxmox-lab.env"* &&
      $(cat "$t/seen-rebuild.env") == *"k8s-restore.yml -e k8s_backup_enabled=false"* && -e $t/work/state/prod-stable-folders &&
      $out == *"owner tap $tap"* && $out == *"restore test passed: volume restore test, 4 folders, 1 database dumps, snapshot 36fe4321"*"etcd restore test"*"snapshot c5523412"* && $out == *"PASS: rebuild-prod: prod torn down and built again"* &&
      -z $(ls -d /dev/shm/rebuild-prod-seal.test-* 2>/dev/null) ]]; then
  ok "6. rebuild: the checks before a teardown in order, the certificates kept, then the one command with prod's stages"
else bad "6. $rc [$order] [$stages] $out"; fi

# 7
printf 'J%.0s' {1..32} > "$t/node.key"; run rebuild "$tap"; r7a=$rc o7a=$out c7a=$calls
printf 'K%.0s' {1..32} > "$t/node.key"; DRILL_RC=2 run rebuild "$tap"; r7b=$rc o7b=$out c7b=$calls
DRILL_NOSNAP=1 run rebuild "$tap"; r7c=$rc o7c=$out c7c=$calls
if [[ $r7a -eq 1 && $o7a == *"differs from the seal node's key"* && $c7a != *one-command* && $c7a != *job* &&
      $r7b -eq 1 && $o7b == *"backup and restore test before the teardown failed"* && $c7b != *one-command* && $c7b != *"ssh "*backup.pem* &&
      $r7c -eq 1 && $o7c == *"named no tested volume snapshot"* && $c7c != *one-command* && $c7c != *"ssh "*backup.pem* ]]; then
  ok "7. a differing seal key, a failed backup test, or a drill that names no tested snapshot destroys nothing"
else bad "7. $r7a $o7a | $r7b $o7b | $r7c $o7c"; fi

# 8
run log
if [[ $rc -eq 0 && $out == *"rebuild-prod: rebuild at central-hub ${sha:0:12}, owner tap $tap"* ]]; then ok "8. log prints the run's lines"
else bad "8. $rc $out"; fi

exit "$fail"
