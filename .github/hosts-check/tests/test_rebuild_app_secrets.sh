#!/usr/bin/env bash
# The dev rebuild's stage app-secrets and its gate, with stand-ins for the secrets store's wrapper:
#   1. The box's rebuild wrapper (hosts/ansible/roles/agent_box/files/rebuild.sh, app_secrets_gate) keeps the gate shut,
#      with the first reason, while the settings' sops_copies is not true (no settings file, missing, false or the
#      string "true"), then while box_cidr is missing, then while the rebuild hold is set; a missing or empty CA file
#      no longer shuts it (each run's store makes its own CA). Only with all three does it set APP_SECRETS_HOOK, to
#      secrets-store.sh put-apps, then compare, and APP_SECRETS_CACERT, to the CA file's path. The lines it prints
#      read back, sourced, as exactly those values.
#   2. The wrapper calls the gate once, inside the in-cluster block and after the hold is written, and puts its line
#      into rebuild.env.
#   3. hosts/rebuild-k8s.sh's stage app-secrets with the gate shut: one SKIP line naming the reason (sops_copies first),
#      rc 0, and the stand-in wrapper never runs; with no gate line at all (an older box wrapper), a SKIP line too.
#   4. With the gate open, the stage runs put-apps, then compare, through the stand-in; a put-apps that fails stops the
#      stage before compare, and a compare that fails fails the stage.
#   5. With the gate open, the stage first writes this run's store CA to APP_SECRETS_CACERT from a stand-in kc that
#      gives ca.crt of Secret openbao/openbao-tls, replacing an earlier run's file, and asks kc for that one field only.
#      kc failing, giving a key with the certificate, or giving no certificate fails the stage with the file unchanged
#      and nothing run. A gate line with no APP_SECRETS_CACERT (an older box wrapper) runs the hook as before.
#   6. The CA file that stage writes never turns on the old store-VM wiring while the in-cluster switch is on: with the
#      CA file, the rebuild role's two ID files and the settings all present, rebuild.sh's wiring block leaves store_url
#      empty when openbao-in-cluster reads true, and still sets it when the switch is off or missing.
# Usage: .github/hosts-check/tests/test_rebuild_app_secrets.sh   (needs python3 and openssl)
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
sed -n '/^hook() {/p;/^store_ca() {$/,/^}$/p;/^run_stage() {/,/^}/p' "$script" > "$t/stage.sh"
grep -q 'app-secrets)' "$t/stage.sh" && grep -q '^hook() {' "$t/stage.sh" || { echo "FAIL: stage app-secrets or hook() was not found in rebuild-k8s.sh"; exit 1; }
grep -q '^store_ca() {$' "$t/stage.sh" || echo "note: store_ca() was not found in rebuild-k8s.sh"

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
# The store's CA as a stand-in kc gives it (stage 4 and 5), a key beside it, and no certificate at all.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$t/kc-key" -out "$t/kc-cert" -days 1 \
  -subj /CN=openbao-ca >/dev/null 2>&1 || { echo "FAIL: openssl could not make a test certificate"; exit 1; }
cat "$t/kc-cert" "$t/kc-key" > "$t/kc-both"; echo "not a certificate" > "$t/kc-none"

# 1
r1=""
for s in none '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32"}' \
         '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32", "sops_copies": false}' \
         '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32", "sops_copies": "true"}'; do
  gate "$s" yes no; r1+="$rc:$([[ $line == 'APP_SECRETS_SKIP="sops_copies is off: '*"the owner's tap (D-0058 rule 9); nothing written\"" ]] && echo tap) "
done
gate '{"address": "bao-dev.invalid", "box_cidr": "192.0.2.30/32", "sops_copies": false}' no yes; r1+="$rc:$([[ $line == *'sops_copies is off'* ]] && echo first) "
gate '{"address": "bao-dev.invalid", "sops_copies": true}' yes no; r1+="$rc:$([[ $line == APP_SECRETS_SKIP=*'no box_cidr'* ]] && echo cidr) "
gate "$open" no yes; r1+="$rc:$([[ $line == APP_SECRETS_SKIP=*'rebuild hold is set'* ]] && echo hold) "
gate "$open" no no; r1+="$rc:$([[ $line == APP_SECRETS_HOOK=* ]] && echo noca) "
gate "$open" empty no; r1+="$rc:$([[ $line == APP_SECRETS_HOOK=* ]] && echo emptyca) "
gate "$open" yes no; r1+="$rc:$line"
want1="0:tap 0:tap 0:tap 0:tap 0:first 0:cidr 0:hold 0:noca 0:emptyca 0:APP_SECRETS_HOOK=\"$t/libexec/secrets-store.sh put-apps && $t/libexec/secrets-store.sh compare\""$'\n'"APP_SECRETS_CACERT=\"$t/ca.crt\""
read_back=$(bash -c '. /dev/stdin; printf "%s|%s|%s" "${APP_SECRETS_HOOK:-}" "${APP_SECRETS_SKIP:-}" "${APP_SECRETS_CACERT:-}"' <<<"$line")
gate '{"sops_copies": false}' yes no
skip_back=$(bash -c '. /dev/stdin; printf "%s|%s" "${APP_SECRETS_HOOK:-}" "${APP_SECRETS_SKIP:-}"' <<<"$line")
if [[ $r1 == "$want1" && $read_back == "$t/libexec/secrets-store.sh put-apps && $t/libexec/secrets-store.sh compare||$t/ca.crt" &&
      $skip_back == "|sops_copies is off: SOPS copies of the apps' secrets wait for the owner's tap (D-0058 rule 9); nothing written" ]]; then
  ok "1. the gate stays shut on sops_copies, then box_cidr, then the hold, in that order, not on the CA file; open, it names put-apps then compare and the CA path; each line reads back as written"
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
  : > "$t/kc-args"
  out=$(printf '%s\n' "$1" > "$t/env"; KC_ARGS=$t/kc-args KC_OUT=${KC_OUT:-$t/kc-cert} ENV_NAME=dev OPENBAO_SEAL_KEY_FILE=/k repo=$t INVENTORY=/inv/ bash -c '
    ap() { echo "AP $*"; }
    kc() { echo "$*" >> "$KC_ARGS"; [ -z "${KC_FAIL:-}" ] || return 1; base64 < "$KC_OUT"; }
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

# 5
gate "$open" no no; open_line=$line
echo "earlier run's CA" > "$t/ca.crt"
stage "$open_line"; r5a=$rc o5a=$out c5a=$sc k5a=$(cat "$t/kc-args")
same=$(cmp -s "$t/ca.crt" "$t/kc-cert" && echo yes)
r5=""
for v in fail both none; do
  echo "earlier run's CA" > "$t/ca.crt"
  if [[ $v == fail ]]; then KC_FAIL=1 stage "$open_line"; else KC_OUT=$t/kc-$v stage "$open_line"; fi
  r5+="$v:$([[ $rc != 0 ]] && echo failed):$sc:$(grep -c "earlier run's CA" "$t/ca.crt"):$([[ -e $t/ca.crt.part ]] && echo part)$([[ $out == *'nothing written'* ]] && echo said) "
done
# An older box wrapper's gate line, with no APP_SECRETS_CACERT: the hook runs, and kc is never called.
stage "$(printf '%s\n' "$open_line" | grep '^APP_SECRETS_HOOK=')"; r5o=$rc c5o=$sc k5o=$(cat "$t/kc-args")
if [[ $r5a == 0 && $same == yes && $c5a == "put-apps compare " && $k5a == "-n openbao get secret openbao-tls -o 'jsonpath={.data.ca\.crt}'" &&
      $o5a == *"app-secrets: the store's CA written to $t/ca.crt (subject=CN"*"openbao-ca"*"PASS: compare:"* &&
      $r5 == "fail:failed::1:said both:failed::1:said none:failed::1:said " && $r5o == 0 && $c5o == "put-apps compare " && -z $k5o ]]; then
  ok "5. gate open: the store's CA (ca.crt only) replaces the earlier file before put-apps; a failed read, a key beside it or no certificate fails with nothing written or run; an older wrapper's line runs as before"
else bad "5. $r5a [$o5a] [$c5a] [$k5a] same=$same | [$r5] | $r5o [$c5o] [$k5o]"; fi

# 6
sed -n '/^store_keys=\$keys\/dev$/,/^fi$/p' "$box" > "$t/wiring.sh"
grep -q 'store_url=https://' "$t/wiring.sh" || { echo "FAIL: the store-VM wiring block was not found in rebuild.sh"; exit 1; }
mkdir -p "$t/w6/keys/dev" "$t/w6/work"
for f in openbao-rebuild-role-id openbao-rebuild-secret-id secrets-store-ca.crt; do echo x > "$t/w6/keys/dev/$f"; done
echo '{"address": "192.0.2.40"}' > "$t/w6/work/secrets-store.json"
wiring() { # in-cluster file content, or "none": prints store_url
  if [[ $1 == none ]]; then rm -f "$t/w6/work/openbao-in-cluster"; else echo "$1" > "$t/w6/work/openbao-in-cluster"; fi
  keys=$t/w6/keys work=$t/w6/work bash -c 'store_url=""; . "$1"; printf "%s" "$store_url"' _ "$t/wiring.sh" 2>&1
}
r6="on:[$(wiring true)] off:[$(wiring false)] none:[$(wiring none)]"
if [[ $r6 == "on:[] off:[https://192.0.2.40] none:[https://192.0.2.40]" ]]; then
  ok "6. with the in-cluster switch on, the CA file and the rebuild IDs never turn on the old store-VM wiring; off or missing, they still do"
else bad "6. $r6"; fi

exit $fail
