#!/usr/bin/env bash
# The dev rebuild's stage app-secrets and its gate, with stand-ins for the secrets store's wrapper:
#   1. The box's rebuild wrapper (hosts/ansible/roles/agent_box/files/rebuild.sh, app_secrets_gate) keeps the gate shut,
#      with the first reason, while the settings' sops_copies is not true (no settings file, missing, false or the
#      string "true"), then while box_cidr is missing, then while the store's CA file is missing or empty, then while
#      the rebuild hold is set; only with all four does it set APP_SECRETS_HOOK, to secrets-store.sh put-apps, then
#      compare. The line it prints reads back, sourced, as exactly that value.
#   2. The wrapper calls the gate once, inside the in-cluster block and after the hold is written, and puts its line
#      into rebuild.env.
#   3. hosts/rebuild-k8s.sh's stage app-secrets with the gate shut: one SKIP line naming the reason (sops_copies first),
#      rc 0, and the stand-in wrapper never runs; with no gate line at all (an older box wrapper), a SKIP line too.
#   4. With the gate open, the stage runs put-apps, then compare, through the stand-in; a put-apps that fails stops the
#      stage before compare, and a compare that fails fails the stage.
# Usage: .github/hosts-check/tests/test_rebuild_app_secrets.sh   (needs python3)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
box=$root/hosts/ansible/roles/agent_box/files/rebuild.sh
script=$root/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

sed -n '/^app_secrets_gate() {$/,/^}$/p' "$box" > "$t/gate.sh"
grep -q 'APP_SECRETS_HOOK' "$t/gate.sh" || { echo "FAIL: app_secrets_gate was not found in rebuild.sh"; exit 1; }
sed -n '/^hook() {/p;/^run_stage() {/,/^}/p' "$script" > "$t/stage.sh"
grep -q 'app-secrets)' "$t/stage.sh" && grep -q '^hook() {' "$t/stage.sh" || { echo "FAIL: stage app-secrets or hook() was not found in rebuild-k8s.sh"; exit 1; }

# Stand-in for /usr/local/libexec/agent-box/secrets-store.sh: records each action; FAIL_<action>=1 makes it fail.
mkdir -p "$t/libexec"
cat > "$t/libexec/secrets-store.sh" <<EOF
#!/bin/bash
echo "\$1" >> "$t/calls"
v=FAIL_\${1//-/_}
[[ -z \${!v:-} ]] || { echo "stand-in \$1 failed" >&2; exit 1; }
case \$1 in
  put-apps) echo "secrets-store: put-apps: 3 values from rebuild-secret-source.env at c1/<name> key value" ;;
  compare) echo "PASS: compare: 5 keys equal in SOPS and OpenBao" ;;
esac
EOF
chmod +x "$t/libexec/secrets-store.sh"

gate() { # settings-json-or-none ca(yes|empty|no) hold(yes|no): the gate's line in $line, its rc in $rc
  if [[ $1 == none ]]; then rm -f "$t/settings.json"; else echo "$1" > "$t/settings.json"; fi
  case $2 in yes) echo CA > "$t/ca.crt" ;; empty) : > "$t/ca.crt" ;; *) rm -f "$t/ca.crt" ;; esac
  if [[ $3 == yes ]]; then date -u > "$t/hold"; else rm -f "$t/hold"; fi
  line=$(libexec=$t/libexec bash -c '. "$1"; app_secrets_gate "$2" "$3" "$4"' _ "$t/gate.sh" "$t/settings.json" "$t/ca.crt" "$t/hold")
  rc=$?
}
open='{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32", "sops_copies": true}'

# 1
r1=""
for s in none '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32"}' \
         '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32", "sops_copies": false}' \
         '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32", "sops_copies": "true"}'; do
  gate "$s" yes no; r1+="$rc:$([[ $line == 'APP_SECRETS_SKIP="sops_copies is off: '*"the owner's tap (D-0058 rule 9); nothing written\"" ]] && echo tap) "
done
gate '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32", "sops_copies": false}' no yes; r1+="$rc:$([[ $line == *'sops_copies is off'* ]] && echo first) "
gate '{"address": "bao-dev.invalid", "sops_copies": true}' yes no; r1+="$rc:$([[ $line == APP_SECRETS_SKIP=*'no box_cidr'* ]] && echo cidr) "
gate "$open" no no; r1+="$rc:$([[ $line == APP_SECRETS_SKIP=*'no CA file'* ]] && echo ca) "
gate "$open" empty no; r1+="$rc:$([[ $line == APP_SECRETS_SKIP=*'no CA file'* ]] && echo ca) "
gate "$open" yes yes; r1+="$rc:$([[ $line == APP_SECRETS_SKIP=*'rebuild hold is set'* ]] && echo hold) "
gate "$open" yes no; r1+="$rc:$line"
want1="0:tap 0:tap 0:tap 0:tap 0:first 0:cidr 0:ca 0:ca 0:hold 0:APP_SECRETS_HOOK=\"$t/libexec/secrets-store.sh put-apps && $t/libexec/secrets-store.sh compare\""
read_back=$(bash -c '. /dev/stdin; printf "%s|%s" "${APP_SECRETS_HOOK:-}" "${APP_SECRETS_SKIP:-}"' <<<"$line")
gate '{"sops_copies": false}' yes no
skip_back=$(bash -c '. /dev/stdin; printf "%s|%s" "${APP_SECRETS_HOOK:-}" "${APP_SECRETS_SKIP:-}"' <<<"$line")
if [[ $r1 == "$want1" && $read_back == "$t/libexec/secrets-store.sh put-apps && $t/libexec/secrets-store.sh compare|" &&
      $skip_back == "|sops_copies is off: SOPS copies of the apps' secrets wait for the owner's tap (D-0058 rule 9); nothing written" ]]; then
  ok "1. the gate stays shut on sops_copies, then box_cidr, the CA file and the hold, in that order; open, it names put-apps then compare; each line reads back as written"
else bad "1. [$r1] [$read_back] [$skip_back]"; fi

# 2
calls=$(grep -c 'app_secrets_gate "' "$box")
hold_line=$(grep -n 'date -u +%FT%TZ > "$work/state/secrets-store.rebuilding"' "$box" | cut -d: -f1)
gate_line=$(grep -n 'app_secrets_env=$(app_secrets_gate "$work/secrets-store.json" "$store_keys/secrets-store-ca.crt" "$work/state/secrets-store.rebuilding")' "$box" | cut -d: -f1)
in_line=$(grep -n '^  in_cluster=true$' "$box" | cut -d: -f1)
block_end=$(awk -v s="$in_line" 'NR > s && /^fi$/ {print NR; exit}' "$box")
env_line=$(awk '/> "\$envdir\/rebuild.env" <<ENV$/ {on=1} on && /^\$app_secrets_env$/ {print "yes"; exit} on && /^ENV$/ {exit}' "$box")
if [[ $calls == 1 && -n $hold_line && -n $gate_line && $hold_line -lt $gate_line && $in_line -lt $gate_line && $gate_line -lt $block_end &&
      $env_line == yes ]] && grep -q '^app_secrets_env=""$' "$box"; then
  ok "2. the wrapper calls the gate once, in the in-cluster block after the hold, and writes its line into rebuild.env"
else bad "2. calls=$calls hold=$hold_line gate=$gate_line in=$in_line end=$block_end env=$env_line"; fi

# The stage, from rebuild-k8s.sh, with the gate's line sourced as rebuild.env would be.
stage() { # env-line: the stage's output in $out, its rc in $rc, the stand-in's calls in $sc
  : > "$t/calls"
  out=$(printf '%s\n' "$1" > "$t/env"; ENV_NAME=dev OPENBAO_SEAL_KEY_FILE=/k repo=$t INVENTORY=/inv/ bash -c '
    ap() { echo "AP $*"; }
    . "$1"; . "$2"
    set +e
    (set -e; run_stage app-secrets); echo "rc=$?"' _ "$t/stage.sh" "$t/env" 2>&1)
  rc=${out##*rc=}; sc=$(tr '\n' ' ' < "$t/calls")
}

# 3
gate '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32"}' yes no; stage "$line"; r3a=$rc o3a=$out c3a=$sc
gate '{"address": "bao-dev.invalid", "sops_copies": true}' yes no; stage "$line"; r3b=$rc o3b=$out c3b=$sc
stage ""; r3c=$rc o3c=$out c3c=$sc
if [[ $r3a == 0 && $o3a == "SKIP: app-secrets: sops_copies is off: SOPS copies of the apps' secrets wait for the owner's tap (D-0058 rule 9); nothing written"$'\n'"rc=0" && -z $c3a &&
      $r3b == 0 && $o3b == "SKIP: app-secrets: no box_cidr"* && -z $c3b &&
      $r3c == 0 && $o3c == "SKIP: app-secrets: not run, the rebuild wrapper on the box set no gate"* && -z $c3c ]]; then
  ok "3. gate shut: one SKIP line naming the reason (sops_copies first), rc 0, nothing run; no gate line: a SKIP line too"
else bad "3. $r3a [$o3a] [$c3a] | $r3b [$o3b] [$c3b] | $r3c [$o3c] [$c3c]"; fi

# 4
gate "$open" yes no
stage "$line"; r4a=$rc o4a=$out c4a=$sc
FAIL_put_apps=1 stage "$line"; r4b=$rc c4b=$sc
FAIL_compare=1 stage "$line"; r4c=$rc c4c=$sc
if [[ $r4a == 0 && $c4a == "put-apps compare " && $o4a == *"secrets-store: put-apps: 3 values"*"PASS: compare: 5 keys equal"* && $o4a != *SKIP* &&
      $r4b != 0 && $c4b == "put-apps " && $r4c != 0 && $c4c == "put-apps compare " ]]; then
  ok "4. gate open: put-apps, then compare; a failed put-apps stops before compare, a failed compare fails the stage"
else bad "4. $r4a [$o4a] [$c4a] | $r4b [$c4b] | $r4c [$c4c]"; fi

exit $fail
