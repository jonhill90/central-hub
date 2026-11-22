#!/usr/bin/env bash
# The inventory wrapper (hosts/ansible/roles/agent_box/files/inventory.sh; docs/specs/2026-11-private-values-on-the-box.md)
# reads and edits the private inventory without printing a value. This runs it against a made-up inventory in a temp folder,
# with the repository's own editable-values.yml, and checks the spec's acceptance lines for it:
#   1. set refuses an unlisted path, a bad type, and a secret key; the classed paths need a message ID.
#   2. set of a listed key changes only that key, and the log holds the path, class and two 12-hex prefixes and no value.
#   3. get, names and diff print no sample address, name or email.
#   4. view <part> returns that group and all.vars, never the agent_box group; an unknown part is refused.
#   5. import fills a first copy only; import-compare names the one path that differs.
# Run from the repository root's checkout.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(cd "$here/../.." && pwd)
wrapper=$root/hosts/ansible/roles/agent_box/files/inventory.sh
list=$root/hosts/ansible/inventories/home/editable-values.yml
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "not ok  $1"; fail=1; }

mkdir -p "$t/libexec/ansible-venv/bin" "$t/keys/inventory" "$t/work" "$t/sealed"
ln -s "$(command -v python3)" "$t/libexec/ansible-venv/bin/python3"
cp "$list" "$t/libexec/editable-values.yml"
sed -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^work=.*|work=$t/work|" \
  -e "s|^store=.*|store=$t/keys/inventory/hosts.yml|" -e "s|^tagkey=.*|tagkey=$t/keys/inventory/tag.key|" -e "s|^prev=.*|prev=$t/keys/inventory/hosts.yml.prev|" \
  -e "s|^recipients=.*|recipients=$t/keys/inventory/recipients.txt|" -e "s|^sealed=.*|sealed=$t/sealed/inventory.sops.json|" \
  -e "s|^prod_cmd=.*|prod_cmd=(cat $t/prod.yml)|" -e "s|^guard_cmd=.*|guard_cmd=(cat $t/guard.yml)|" "$wrapper" > "$t/inventory.sh"
for v in libexec work store tagkey prev recipients sealed; do
  grep -q "^$v=$t" "$t/inventory.sh" || { bad "the wrapper no longer sets $v on its own line, so the test can't point it at the temp folder"; exit 1; }
done
for v in prod_cmd guard_cmd; do
  grep -q "^$v=(cat $t/" "$t/inventory.sh" || { bad "the wrapper no longer sets $v on its own line"; exit 1; }
done
# The real lines read the two old copies with exactly the commands the role's sudoers file allows (sudoers.j2, inventory first fill).
grep -qxF 'prod_cmd=(sudo -n -u keys /usr/bin/cat /etc/agent-keys/prod/inventory-hosts.yml)' "$wrapper" \
  && grep -qxF 'guard_cmd=(sudo -n -u guardops /usr/bin/cat /etc/agent-keys-guard/inventory/hosts.yml)' "$wrapper" \
  && ok "the wrapper reads the prod and guard copies through the two exact sudo commands" || bad "the import commands changed"
# A stand-in for sops: it records its arguments and "encrypts" by base64 into --output (this tests the wrapper's plumbing, not sops).
cat > "$t/libexec/sops" <<'EOS'
#!/bin/bash
[ -n "${FAKE_SOPS_FAIL:-}" ] && exit 1
out=""; prev=""; for a in "$@"; do [[ $prev == --output ]] && out=$a; prev=$a; done
printf '%s\n' "$*" > "${out%/*}/sops.args"
{ echo SEALED; base64 -w0 -- "${@: -1}"; } > "$out"
EOS
chmod +x "$t/libexec/sops"
R1=age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq R2=age1pppppppppppppppppppppppppppppppppppppppppppppppppppppppppp
inv() { bash "$t/inventory.sh" "$@"; }

# Sample values the output must never show.
ADDR=10.9.8.7 ADDR2=10.9.8.99 HOST=secretbox01 MAIL=owner@example.org ZONE=lab.example.org
cat > "$t/prod.yml" <<EOF
---
all:
  vars:
    k8s_gateway_address: "$ADDR"
  children:
    proxmox:
      hosts:
        proxmox_host:
          proxmox_firewall_enable: false
          proxmox_firewall_extra_rules: []
          proxmox_notify_ntfy_url: "https://ntfy.$ZONE/alerts"
          proxmox_cert_names: ["$HOST.$ZONE"]
    agent_box:
      hosts:
        agent_box_vm:
          agent_box_hostname: "$HOST"
    opnsense:
      hosts:
        opnsense_fw:
          opnsense_api_key: "KEYVALUE1"
          opnsense_dns_zone: "$ZONE"
    k8s_nodes:
      hosts:
        $HOST:
          ansible_host: "$ADDR2"
      vars:
        k8s_certs_acme_email: "$MAIL"
        k8s_certs_issue: false
EOF
cp "$t/prod.yml" "$t/guard.yml"
sed -i 's/^        k8s_certs_issue: false$/&\n        k8s_gitops_source_app_secrets_store: openbao/' "$t/prod.yml"

# 5. first fill. With no recipients file the copy is made and the seal is refused with a message and exit 3.
rc=0; out=$(inv import prod 2>&1) || rc=$?
[ "$rc" = 3 ] && [ -s "$t/keys/inventory/hosts.yml" ] && [ ! -e "$t/sealed/inventory.sops.json" ] && echo "$out" | grep -q 'recipients.txt is missing' \
  && ok "no recipients file: the first copy is written, the seal is refused (exit 3) and says why" || bad "no recipients file: rc=$rc out=[$out]"
rm -f "$t/keys/inventory/hosts.yml"
printf '%s\n%s\n' "$R1" "$R2" > "$t/keys/inventory/recipients.txt"
out=$(inv import prod 2>&1) && ok "import prod fills the first copy and seals it: $out" || bad "import prod failed: $out"
out=$(inv import prod 2>&1) && bad "a second import was accepted" || ok "a second import is refused"
[ "$(stat -c %a "$t/keys/inventory/hosts.yml")" = 600 ] && ok "the working copy is mode 0600" || bad "the working copy is not mode 0600"
out=$(inv import-compare 2>&1); echo "$out" | grep -qx 'only in prod: k8s_nodes.k8s_gitops_source_app_secrets_store' && echo "$out" | grep -q ' 1 key path(s)' \
  && ok "import-compare names the one path that differs" || bad "import-compare gave [$out]"

# 5b. the sealed copy
[ -s "$t/sealed/inventory.sops.json" ] && [ "$(stat -c %a "$t/sealed/inventory.sops.json")" = 640 ] && ok "the sealed copy exists, mode 0640 (the keys user's group reads it)" || bad "the sealed copy is missing or its mode is wrong"
grep -q "^--encrypt\|^encrypt --input-type binary --output-type json --age $R1,$R2 " "$t/sealed/sops.args" && ok "sops got both recipients, binary input and JSON output" || bad "sops args: $(cat "$t/sealed/sops.args")"
! grep -q "$ADDR" "$t/sealed/inventory.sops.json" && ok "the sealed file does not hold a sample address in the clear" || bad "the sealed file shows a sample address"
left=$(find "$t/sealed" -name '*.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]' | head -1)
if [ -n "$left" ]; then bad "a temp file was left in the sealed folder"; else ok "no temp file is left in the sealed folder"; fi
cp "$t/sealed/inventory.sops.json" "$t/sealed.before"
printf 'age1bad\n' > "$t/keys/inventory/recipients.txt"
rc=0; inv seal >/dev/null 2>"$t/err" || rc=$?
[ "$rc" = 3 ] && cmp -s "$t/sealed.before" "$t/sealed/inventory.sops.json" && ok "a bad recipient line: seal refused (exit 3) and the earlier sealed copy is kept" || bad "bad recipient: rc=$rc"
printf '%s\n%s\n' "$R1" "$R2" > "$t/keys/inventory/recipients.txt"
rc=0; FAKE_SOPS_FAIL=1 inv seal >/dev/null 2>"$t/err" || rc=$?
[ "$rc" = 3 ] && cmp -s "$t/sealed.before" "$t/sealed/inventory.sops.json" && [ "$(ls "$t/sealed" | wc -l)" = 2 ] && ok "sops failing: seal refused (exit 3), the earlier copy and no temp file are left" || bad "sops failing: rc=$rc files=$(ls "$t/sealed")"

# 1. refusals
refuse() { # what, then the command; the command must fail and the working copy must not change
  local what=$1; shift
  local before; before=$(sha256sum "$t/keys/inventory/hosts.yml")
  if printf '%s' "$VAL" | inv "$@" >/dev/null 2>"$t/err"; then bad "$what was accepted"
  elif [ "$(sha256sum "$t/keys/inventory/hosts.yml")" = "$before" ]; then ok "$what is refused: $(head -c 90 "$t/err")"
  else bad "$what was refused but the file changed"; fi
}
VAL=x refuse "an unlisted path" set proxmox_host.not_listed
VAL=x refuse "a secret key" set opnsense_fw.opnsense_api_key
VAL=x refuse "a key with 'token' in its name" set opnsense_fw.some_api_token
VAL=300 refuse "a bad address for a listed address path" set all.k8s_gateway_address cmsg_0123456789abc
VAL=true refuse "a classed path with no message ID" set proxmox_host.proxmox_firewall_enable
VAL=maybe refuse "a bad bool" set k8s_nodes.k8s_certs_issue
VAL=sops refuse "a choice outside its values" set all.k8s_gitops_source_app_secrets_store
VAL='[{action: ACCEPT, source: "10.1.2.3", proto: tcp, dport: 443}]' refuse "a rule with a source that is not a CIDR" set proxmox_host.proxmox_firewall_extra_rules cmsg_0123456789abc
VAL=x refuse "a path with no scope dot" set nodots
VAL=x refuse "a bad message ID" set k8s_nodes.k8s_certs_issue notacmsg

# 2. set of one listed key
cp "$t/keys/inventory/hosts.yml" "$t/before.yml"
out=$(printf 'true' | inv set k8s_nodes.k8s_certs_issue 2>&1) && ok "set of a plain bool without a message ID is accepted (and seals): $out"
! cmp -s "$t/sealed.before" "$t/sealed/inventory.sops.json" && ok "a set seals again: the sealed copy changed" || bad "the sealed copy did not change after a set"
true || bad "set failed: $out"
python3 -I - "$t/before.yml" "$t/keys/inventory/hosts.yml" <<'PY' && ok "set changed only that key" || bad "set changed more than the one key"
import sys, yaml
a, b = (yaml.safe_load(open(p)) for p in sys.argv[1:3])
def flat(n, p=""):
    if isinstance(n, dict):
        for k, v in n.items(): yield from flat(v, p + "/" + str(k))
    else: yield p, n
fa, fb = dict(flat(a)), dict(flat(b))
diff = [k for k in set(fa) | set(fb) if fa.get(k) != fb.get(k)]
sys.exit(0 if diff == ["/all/children/k8s_nodes/vars/k8s_certs_issue"] else 1)
PY
out=$(printf '"10.9.8.55/32"' | inv set proxmox_host.proxmox_firewall_home_lan_cidr cmsg_0123456789abc 2>&1) && ok "set of a firewall-class value with a message ID is accepted" || bad "firewall-class set failed: $out"
log=$(inv log)
echo "$log" | grep -Eq '"before": "[0-9a-f]{12}"' && echo "$log" | grep -Eq '"after": "[0-9a-f]{12}"' && echo "$log" | grep -q '"path": "proxmox_host.proxmox_firewall_home_lan_cidr"' \
  && echo "$log" | grep -q '"class": "firewall"' && ! echo "$log" | grep -q '10.9.8.55' \
  && ok "the log holds the path, class, relay ID and two 12-hex prefixes, and no value" || bad "the log is wrong: $log"

printf 'c1' | inv set all.k8s_gitops_source_app_secrets_store >/dev/null && inv get all.k8s_gitops_source_app_secrets_store | grep -Eq '^choice [0-9a-f]{12}$' \
  && ok "the listed choice path (its name has 'secret' in it) takes a value from its list" || bad "the listed choice path was refused"
# 3. nothing private in get, names, diff, log
printf '[{action: ACCEPT, source: "10.9.8.0/24", proto: tcp, dport: 443}]' | inv set proxmox_host.proxmox_firewall_extra_rules cmsg_0123456789abc >/dev/null
rules_diff=$(inv diff)
printf '"admin@private.example.com"' | inv set k8s_nodes.k8s_certs_acme_email >/dev/null
all=$( { inv get all.k8s_gateway_address; inv get k8s_nodes.k8s_certs_acme_email; inv names; inv diff; inv log; } 2>&1 )
leak=''
for s in "$ADDR" "$ADDR2" "$HOST" "$MAIL" "$ZONE" 10.9.8.55 10.9.8.0 private.example.com KEYVALUE1; do echo "$all" | grep -q "$s" && leak="$leak $s"; done
[ -z "$leak" ] && ok "get, names, diff and log print no sample address, name or email" || bad "output showed:$leak"
inv get all.k8s_gateway_address | grep -Eq '^address [0-9a-f]{12}$' && ok "get prints a type and a 12-hex prefix" || bad "get output: $(inv get all.k8s_gateway_address)"
echo "$rules_diff" | grep -qx 'proxmox_host.proxmox_firewall_extra_rules: changed' && ! echo "$rules_diff" | grep -Eq '10\.9\.8|ACCEPT|443|tcp|<' \
  && ok "diff prints a key path and the word changed for a rules change, no value and no shape" || bad "diff gave: $rules_diff"
inv diff | grep -qx 'k8s_nodes.k8s_certs_acme_email: changed' && ! inv diff | grep -q '<email>' && ok "diff of an email change is the key path and changed only" || bad "diff gave: $(inv diff)"
printf 'true' | inv set k8s_nodes.k8s_certs_issue >/dev/null   # same value as before: nothing changes
inv diff | grep -qx 'inventory: 0 path(s) changed since the copy before the last set' && ok "a set that changes nothing gives 0 changed paths" || bad "diff gave: $(inv diff)"
inv names | grep -qx 'proxmox_host.proxmox_firewall_enable' && ! inv names | grep -q "$HOST" && ok "names lists key paths and no node name" || bad "names output wrong"

# 3b. the tag: HMAC under a key only this user holds
[ "$(stat -c %a "$t/keys/inventory/tag.key")" = 600 ] && [ "$(stat -c %s "$t/keys/inventory/tag.key")" -ge 32 ] && ok "the tag key exists, mode 0600, at least 32 bytes" || bad "the tag key is wrong"
printf 'true' | inv set k8s_nodes.k8s_certs_issue >/dev/null
tag_a=$(inv get k8s_nodes.k8s_certs_issue | cut -d' ' -f2)
plain=$(python3 -c 'import hashlib,json;print(hashlib.sha256(json.dumps(True,sort_keys=True,separators=(",",":")).encode()).hexdigest()[:12])')
[ "$tag_a" != "$plain" ] && ok "the tag of a bool is not the plain SHA-256 prefix, so a fixed table of prefixes does not name it" || bad "the tag equals the plain SHA-256 prefix"
[ "$tag_a" = "$(inv get k8s_nodes.k8s_certs_issue | cut -d' ' -f2)" ] && ok "the same value under the same key gives the same tag" || bad "the tag is not stable"
cp "$t/keys/inventory/tag.key" "$t/key.old"; head -c 32 /dev/urandom > "$t/keys/inventory/tag.key"
tag_b=$(inv get k8s_nodes.k8s_certs_issue | cut -d' ' -f2)
[ "$tag_a" != "$tag_b" ] && ok "the same value under two different keys gives different tags" || bad "two keys gave the same tag"
keyhex=$(python3 -c 'import sys;print(open(sys.argv[1],"rb").read().hex())' "$t/key.old")
leakkey=$( { inv get k8s_nodes.k8s_certs_issue; inv log; inv names; inv diff; } 2>&1 | grep -c "$keyhex" || true )
[ "$leakkey" = 0 ] && ok "no action prints the key" || bad "the key was printed"
rm -f "$t/keys/inventory/tag.key"; inv get k8s_nodes.k8s_certs_issue >/dev/null && [ -s "$t/keys/inventory/tag.key" ] && ok "a missing key is made on first use" || bad "a missing key was not made"

# 4. view
v=$(inv view proxmox)
echo "$v" | grep -q 'proxmox_host:' && echo "$v" | grep -q 'k8s_gateway_address' && ! echo "$v" | grep -q 'agent_box' && ! echo "$v" | grep -q 'k8s_certs_acme_email' \
  && ok "view proxmox returns the proxmox group and all.vars only" || bad "view proxmox gave: $v"
inv view agent_box >/dev/null 2>&1 && bad "view agent_box was accepted" || ok "view agent_box is refused"
inv view nonsense >/dev/null 2>&1 && bad "view of an unknown part was accepted" || ok "view of an unknown part is refused"

# The list itself: each entry's class is known, and no entry names a secret-looking variable.
python3 -I - "$list" <<'PY' && ok "editable-values.yml: known types and classes, none of the refused names, no value" || bad "editable-values.yml has a bad entry"
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
types = {"address", "cidr", "cidrs", "port", "bool", "name", "names", "url", "email", "choice", "rules"}
classes = {"plain", "firewall", "tailnet", "access", "money"}
bad = [e["path"] for e in d["entries"]
       if e["type"] not in types or e["class"] not in classes or e["path"].split(".", 1)[1] in d["refused"]
       or set(e) - {"path", "part", "type", "class", "values"}]
sys.exit(1 if bad else 0)
PY
bash -n "$wrapper" && ok "the wrapper parses" || bad "the wrapper does not parse"
exit "$fail"
