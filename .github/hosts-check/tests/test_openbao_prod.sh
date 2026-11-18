#!/usr/bin/env bash
# The openbao-prod wrapper's own checks (hosts/ansible/roles/agent_box/files/openbao-prod.sh), with stand-ins for git,
# ansible-inventory, ansible-playbook, ssh, sops and age-keygen:
#   1. Usage: no action, another action, seal with no tap id or a malformed one: usage errors, nothing run.
#   2. key makes the box's prod node key once and prints only its public half; a second run keeps the same key.
#   3. Before any playbook: no settings, a seal_node that is not a prod node, a box_cidr wider than one address, or a
#      host labelled env dev each refuse.
#   4. The box's inventory copy: the Mac's ssh arguments, key and proxmox group are gone; the box's key and plain ssh,
#      the in-cluster store, its seal node, store name and box address are set.
#   5. gitops runs k8s-gitops.yml --tags source only, on that copy.
#   6. handover makes the admin IDs once, names their files to the play, and prints neither ID.
#   7. log prints the run's own lines.
#   8. seal-copy: reads the seal node's key over ssh and keeps it as the SOPS copy, never printed; a second run only
#      compares; a node key that differs fails and replaces nothing; a key that is not 32 bytes is refused; seal with a
#      SOPS copy already kept makes no new key.
# Usage: .github/hosts-check/tests/test_openbao_prod.sh   (needs python3 with PyYAML, ssh-keygen, flock)
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
cat > "$t/bin/git" <<'EOF'
#!/bin/bash
case "$*" in
  *"remote get-url"*) echo https://example.invalid/central-hub.git ;;
  clone*) mkdir -p "${@: -1}/.git" "${@: -1}/hosts/ansible" ;;
  *rev-parse*) echo abc1234 ;;
esac
exit 0
EOF
# ansible-inventory --list: hosts per group (direct and through children) and each host's vars, group vars first.
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
if "--host" in sys.argv: print(json.dumps(hv[sys.argv[sys.argv.index("--host") + 1]])); sys.exit(0)
print(json.dumps(out))
EOF
# ssh: records its arguments and prints the stand-in node's seal key.
cat > "$t/bin/ssh" <<EOF
#!/bin/bash
echo "ssh \${*: -2}" >> $t/calls
cat $t/node.key
EOF
# sops: "encrypts" to a JSON file holding the bytes as base64, and back.
cat > "$t/libexec/sops" <<'EOF'
#!/usr/bin/env python3
import base64, json, sys
a = sys.argv[1:]
out, src = a[a.index("--output") + 1], a[-1]
if a[0] == "encrypt": json.dump({"data": base64.b64encode(open(src, "rb").read()).decode()}, open(out, "w"))
else: open(out, "wb").write(base64.b64decode(json.load(open(src))["data"]))
EOF
cat > "$t/libexec/age-keygen" <<'EOF'
#!/bin/bash
echo age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
EOF
mkdir -p "$t/keys/secrets-bundle"; echo stand-in > "$t/keys/secrets-bundle/age-identity.txt"
cat > "$venv/ansible-playbook" <<EOF
#!/bin/bash
echo "playbook \$*" >> $t/calls
cp "\${2%/}/hosts.yml" $t/seen-inventory.yml
echo "PLAY RECAP"
EOF
chmod +x "$t/bin/git" "$t/bin/ssh" "$t/libexec/sops" "$t/libexec/age-keygen" "$venv/ansible-inventory" "$venv/ansible-playbook"
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^work=.*|work=$t/work|" \
    -e "s|PATH=\$libexec/ansible-venv/bin:/usr/local/bin|PATH=\$libexec/ansible-venv/bin:$t/bin:/usr/local/bin|" \
    hosts/ansible/roles/agent_box/files/openbao-prod.sh > "$t/run/openbao-prod.sh"
grep -q "^keys=$t/keys" "$t/run/openbao-prod.sh" && grep -q "^work=$t/work" "$t/run/openbao-prod.sh" &&
  grep -q ":$t/bin:" "$t/run/openbao-prod.sh" || { echo "FAIL the test could not point the wrapper at its folders"; exit 1; }

run() { : > "$t/calls"; bash "$t/run/openbao-prod.sh" "$@" > "$t/out" 2>&1; rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls"); }
settings() { echo "$1" > "$t/work/openbao-prod.json"; }
inventory() { printf '%s\n' "$@" > "$t/keys/prod/inventory-hosts.yml"; }
prod_inv=("all:" "  children:" "    proxmox:" "      hosts:" "        pve-a: {ansible_host: 192.0.2.1}"
          "    k8s_nodes:" "      vars:" "        ansible_ssh_common_args: -o ProxyJump=root@192.0.2.1"
          "        ansible_ssh_private_key_file: /Users/someone/.ssh/id"
          "      children:" "        k8s_control_plane:" "          hosts:" "            cp-a: {ansible_host: 192.0.2.10}"
          "        k8s_workers:" "          hosts:" "            wk-a: {ansible_host: 192.0.2.11}")

# 1
r1=""
for args in "" "apply" "seal" "seal notatap" "seal cmsg_short" "seal-copy" "seal-copy notatap" "key extra"; do
  # shellcheck disable=SC2086
  run $args; r1+="$rc:${calls:-none} "
done
if [[ $r1 == "2:none 2:none 2:none 2:none 2:none 2:none 2:none 2:none " ]]; then ok "1. usage errors, nothing run"; else bad "1. $r1"; fi

# 2
run key; r2a=$rc o2a=$out
pub1=$(cat "$t/keys/prod-node-key.pub" 2>/dev/null)
run key; pub2=$(cat "$t/keys/prod-node-key.pub" 2>/dev/null)
if [[ $r2a -eq 0 && $o2a == *"$pub1"* && $pub1 == ssh-ed25519* && $pub1 == "$pub2" && $o2a != *"PRIVATE KEY"* ]]; then
  ok "2. key makes the node key once and prints only its public half"
else bad "2. $r2a $o2a"; fi

# 3
inventory "${prod_inv[@]}"
rm -f "$t/work/openbao-prod.json"; run gitops; r3a=$rc o3a=$out c3a=$calls
settings '{"seal_node": "nope", "store_host": "bao.invalid"}'; run gitops; r3b=$rc o3b=$out c3b=$calls
settings '{"seal_node": "wk-a", "store_host": "bao.invalid", "box_cidr": "192.0.2.50/24"}'; run gitops; r3c=$rc o3c=$out c3c=$calls
inventory "${prod_inv[@]}" "      hosts:" "        wk-a: {k8s_gitops_cluster_labels: {env: dev}}"
settings '{"seal_node": "wk-a", "store_host": "bao.invalid"}'; run gitops; r3d=$rc o3d=$out c3d=$calls
if [[ $r3a -ne 0 && $o3a == *"openbao-prod.json is missing"* && $r3b -ne 0 && $o3b == *"seal_node is not a k8s_nodes host"* &&
      $r3c -ne 0 && $o3c == *"box_cidr must be one address"* && $r3d -ne 0 && $o3d == *"labelled env dev"* &&
      -z $c3a$c3b$c3c$c3d ]]; then
  ok "3. no settings, a seal node not in prod, a wide box_cidr or an env dev host: refused before any playbook"
else bad "3. $r3a $o3a | $r3b $o3b | $r3c $o3c | $r3d $o3d"; fi

# 4, 5
inventory "${prod_inv[@]}"
settings '{"seal_node": "wk-a", "store_host": "bao.invalid", "box_cidr": "192.0.2.50/32"}'
run gitops
seen=$(python3 -c 'import json, sys, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$t/seen-inventory.yml" 2>/dev/null)
v=$(python3 -c 'import json, sys; d = json.loads(sys.argv[1]); v = d["all"]["children"]["k8s_nodes"]["vars"]
print(v["ansible_ssh_private_key_file"], v["ansible_ssh_common_args"], v["k8s_gitops_source_openbao_in_cluster"],
      v["k8s_gitops_source_openbao_seal_node"], v["k8s_gitops_source_openbao_store_host"], v["k8s_gitops_source_openbao_box_cidr"],
      "proxmox" in d["all"]["children"])' "$seen" 2>/dev/null)
want="$t/keys/prod-node-key -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$t/work/openbao-prod/known_hosts True wk-a bao.invalid 192.0.2.50/32 False"
if [[ $rc -eq 0 && $v == "$want" && $seen != *ProxyJump* && $seen != */Users/* ]]; then
  ok "4. the box's copy: the Mac's ssh settings and proxmox group gone; the box's key and the store's settings set"
else bad "4. $rc [$v] $out"; fi
if [[ $calls == "playbook -i $t/work/openbao-prod/inventory/ playbooks/k8s-gitops.yml --tags source" && $out == *"prod nodes, plain ssh"* ]]; then
  ok "5. gitops: k8s-gitops.yml --tags source only"
else bad "5. [$calls]"; fi

# 6
run handover; r6a=$rc c6a=$calls o6a=$out
rid=$(cat "$t/keys/prod/openbao-admin-role-id" 2>/dev/null); sid=$(cat "$t/keys/prod/openbao-admin-secret-id" 2>/dev/null)
run handover
if [[ $r6a -eq 0 && ${#rid} -eq 48 && ${#sid} -eq 48 && $rid == "$(cat "$t/keys/prod/openbao-admin-role-id")" &&
      $c6a == *"playbooks/k8s-openbao-handover.yml -e openbao_admin_role_id_file=$t/keys/prod/openbao-admin-role-id -e openbao_admin_secret_id_file=$t/keys/prod/openbao-admin-secret-id"* &&
      $o6a$out != *"$rid"* && $o6a$out != *"$sid"* ]]; then
  ok "6. handover: the IDs made once, their files named to the play, neither printed"
else bad "6. $r6a $c6a"; fi

# 7
run log
if [[ $rc -eq 0 && $out == *"openbao-prod: handover at central-hub abc1234"* && $out == *"PLAY RECAP"* ]]; then ok "7. log prints the run's own lines"
else bad "7. $rc $out"; fi

# 8
tap=cmsg_01ABCDEFGHIJKLMNOPQRSTUVWXYZ
sops_copy=$t/keys/prod/openbao-seal.key.sops.json
printf 'K%.0s' {1..32} > "$t/node.key"
rm -f -- "$sops_copy"
run seal-copy "$tap"; r8a=$rc o8a=$out c8a=$calls
kept=$(python3 -c 'import base64, json, sys; print(base64.b64decode(json.load(open(sys.argv[1]))["data"]).decode())' "$sops_copy" 2>/dev/null)
run seal-copy "$tap"; r8b=$rc o8b=$out
printf 'J%.0s' {1..32} > "$t/node.key"; before=$(cat "$sops_copy")
run seal-copy "$tap"; r8c=$rc o8c=$out; after=$(cat "$sops_copy")
mv "$sops_copy" "$t/kept.json"; printf 'K%.0s' {1..31} > "$t/node.key"
run seal-copy "$tap"; r8d=$rc o8d=$out
mv "$t/kept.json" "$sops_copy"
run seal "$tap"; r8e=$rc c8e=$calls; after_seal=$(cat "$sops_copy")
if [[ $r8a -eq 0 && $o8a == *"PASS: seal-copy: the seal node's key is kept"* && $kept == "$(printf 'K%.0s' {1..32})" &&
      $c8a == "ssh root@192.0.2.11 cat /var/lib/central-hub/openbao-seal/seal-1.key" && $o8a$o8b$o8c != *KKKK* &&
      $o8a == *"owner tap $tap"* && -z $(ls /dev/shm/openbao-prod-seal.* 2>/dev/null) &&
      $r8b -eq 0 && $o8b == *"PASS: seal-copy: the box's SOPS copy and the seal node's key are the same"* &&
      $r8c -eq 1 && $o8c == *"FAIL: seal-copy: the seal node's key differs"* && $before == "$after" &&
      $r8d -ne 0 && $o8d == *"not 32 bytes; nothing kept"* && ! -e $t/keys/prod/openbao-seal.key.sops.json.part &&
      $r8e -eq 0 && $c8e == *"playbooks/k8s-openbao-seal.yml -e openbao_seal_key_file=/dev/shm/openbao-prod-seal."* &&
      $after_seal == "$before" ]]; then
  ok "8. seal-copy keeps the node's key once and then only compares; a differing or short key keeps nothing; seal makes no new key"
else bad "8. $r8a [$c8a] $o8a | $r8b $o8b | $r8c $o8c | $r8d $o8d | $r8e $c8e"; fi

exit "$fail"
