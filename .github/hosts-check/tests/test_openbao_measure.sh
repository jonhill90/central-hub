#!/usr/bin/env bash
# playbooks/k8s-openbao-measure.yml offline, with stub kubectl, curl and openssl:
#   1. probes that OpenBao answers (400 on each path, with audit lines): the last line is the PASS line, with the
#      remote address and X-Forwarded-For each probe's audit line gave, and the ListenerSet's own listener conditions;
#   2. probes that get no HTTP answer at all (curl 28, as on dev run 20261118T212236Z): the play still passes, but its
#      last line is a SKIP line that says nothing was measured, never a PASS line, and keeps curl's error per probe;
#   3. a Gateway answer on path a only (503 while the control Job found the store unsealed): a PASS line, path a
#      "refused at gateway";
#   4. a probe OpenBao answered with no audit line still fails the play.
# Usage: .github/hosts-check/tests/test_openbao_measure.sh   (needs ansible-core)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
play=$root/hosts/ansible/playbooks/k8s-openbao-measure.yml
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
mkdir -p "$w/bin"

# kubectl: the fixed reads the play makes; `exec ... grep` prints one audit line per nonce the curl stub recorded.
cat > "$w/bin/kubectl" <<EOF
#!/usr/bin/env bash
a="\$*"
case "\$a" in
  *"get gateway apps"*)
    printf '%s' '[{"name":"http","conditions":[{"type":"Programmed","status":"True"}]},{"name":"https","conditions":[{"type":"Programmed","status":"True"}]},{"name":"http-short","conditions":[{"type":"Programmed","status":"True"}]},{"name":"https-short","conditions":[{"type":"Programmed","status":"True"}]}]' ;;
  *"get listenerset openbao-measure"*".status.listeners"*) printf '%s' 'openbao-pass:Accepted=False(UnsupportedProtocol), ' ;;
  *"get listenerset openbao-measure"*) printf '%s' 'Accepted=False(ListenersNotValid) Programmed=False(ListenersNotValid) ' ;;
  *"get namespace openbao-measure"*) printf '%s' 'uid-1' ;;
  *"get secret openbao-tls"*|*"get secret apps-tls"*) printf '%s' "\$(printf 'CERT' | base64)" ;;
  *" apply -f -"*) cat > /dev/null; echo "applied" ;;
  *"get httproute openbao-measure"*) printf '%s' 'Accepted=True ResolvedRefs=True ' ;;
  *"get job openbao-measure-control-"*) printf '%s' 's=1 f=' ;;
  *"get job openbao-measure-test-"*) printf '%s' 's= f=1' ;;
  *"logs job/openbao-measure-test-"*) echo 'Error checking seal status: context deadline exceeded (Client.Timeout exceeded)' ;;
  *"logs job/"*) echo 'Sealed false' ;;
  *"exec openbao-0"*)
    [ -s "$w/nonces" ] || exit 1
    [ "\${NO_AUDIT:-}" = 1 ] && exit 1
    while read -r n; do
      printf '{"type":"request","request":{"path":"auth/approle/login","remote_address":"10.0.0.9","headers":{"x-measure-nonce":["%s"],"x-forwarded-for":["192.0.2.50"]}}}\n' "\$n"
    done < "$w/nonces" ;;
  *"get ciliumnodes"*) printf '%s' '10.0.0.9 ' ;;
  *) echo "unexpected kubectl \$a" >&2; exit 3 ;;
esac
EOF
# curl: PROBES=answer (400 everywhere), timeout (curl 28 everywhere) or gw503 (503 on path a and a+xff, 400 on b).
cat > "$w/bin/curl" <<EOF
#!/usr/bin/env bash
nonce=""; host=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -H) case "\$2" in "X-Measure-Nonce: "*) nonce=\${2#X-Measure-Nonce: } ;; esac; shift ;;
    https://*) host=\${1#https://}; host=\${host%%/*} ;;
  esac
  shift
done
case "\${PROBES:-answer}" in
  timeout) printf '000'; echo 'curl: (28) Connection timed out after 15002 milliseconds' >&2; exit 28 ;;
  gw503) case "\$host" in openbao-measure.*) printf '503'; exit 0 ;; esac ;;
esac
echo "\$nonce" >> "$w/nonces"
printf '400'
EOF
cat > "$w/bin/openssl" <<EOF
#!/usr/bin/env bash
case "\$1" in
  s_client) [ "\${PROBES:-answer}" = timeout ] || echo CERT ;;
  x509) [ -n "\$(cat)" ] && echo 'issuer=CN = stub store CA' ;;
esac
EOF
chmod +x "$w/bin/kubectl" "$w/bin/curl" "$w/bin/openssl"

sed 's/^  hosts: k8s_control_plane\[0\]$/  hosts: all/' "$play" > "$w/play.yml"
grep -q '^  hosts: all$' "$w/play.yml" || { echo "FAIL the play's hosts line changed"; exit 1; }
run() {
  rm -f "$w/nonces"
  (cd "$root/hosts/ansible" && PATH="$w/bin:$PATH" ANSIBLE_CONFIG=ansible.cfg ansible-playbook \
    -i "localhost," -e '{"ansible_connection":"local","ansible_become":false}' \
    -e "ansible_python_interpreter=$(command -v python3)" \
    -e k8s_gitops_source_zone=example.invalid -e k8s_gitops_source_gateway_address=192.0.2.10 \
    -e k8s_gitops_source_openbao_in_cluster=true -e measure_image=stub "$w/play.yml") > "$w/out" 2>&1
  rc=$?
  line=$(grep -oE '"msg": "(PASS|SKIP): openbao-measure:[^"]*' "$w/out" | sed 's/^"msg": "//')
}

# 1
PROBES=answer run
if [[ $rc -eq 0 && $line == "PASS: openbao-measure: gateway=ok listenerset=Accepted=False(ListenersNotValid) Programmed=False(ListenersNotValid) [openbao-pass:Accepted=False(UnsupportedProtocol),]; policy=enforced;"* &&
      $line == *"a=400 remote=10.0.0.9 xff=192.0.2.50;"* && $line == *"b=400 remote=10.0.0.9"* && $line == *"b_cert=CN = stub store CA"* ]]; then
  ok "1. answered probes: a PASS line with each probe's remote address and the listener's own conditions"
else bad "1. rc=$rc [$line] $(tail -5 "$w/out")"; fi

# 2
PROBES=timeout run
if [[ $rc -eq 0 && $line == "SKIP: openbao-measure: not measured, no probe got an HTTP answer from the Gateway; gateway=ok"* &&
      $line == *"a=curl: (28) Connection timed out after 15002 milliseconds remote=- xff=-;"* &&
      $line == *"b=curl: (28)"* && $(grep -c 'PASS: openbao-measure' "$w/out") -eq 0 ]]; then
  ok "2. no probe answered: the play passes with a SKIP line saying nothing was measured, never a PASS line"
else bad "2. rc=$rc [$line] $(tail -5 "$w/out")"; fi

# 3
PROBES=gw503 run
if [[ $rc -eq 0 && $line == "PASS: openbao-measure:"* && $line == *"a=503 refused at gateway remote=- xff=-;"* && $line == *"b=400 remote=10.0.0.9"* ]]; then
  ok "3. the Gateway's own 503 on path a: a PASS line with a refused at gateway"
else bad "3. rc=$rc [$line] $(tail -5 "$w/out")"; fi

# 4
NO_AUDIT=1 PROBES=answer run
if [[ $rc -ne 0 && -z $line ]] && grep -q 'a probe reached OpenBao but no audit line' "$w/out"; then
  ok "4. a probe OpenBao answered with no audit line still fails the play"
else bad "4. rc=$rc [$line]"; fi

exit $fail
