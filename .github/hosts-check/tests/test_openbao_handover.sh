#!/usr/bin/env bash
# playbooks/k8s-openbao-handover.yml offline, against a stub kubectl whose `exec ... sh -s` runs the play's
# in-pod script here with a stub `bao`:
#   1. with no box CIDR it hands nothing over and passes with a skip line; a loopback or wider one, or the
#      in-cluster store off, fails it; neither makes any kubectl call;
#   2. a first hand-over signs in as bootstrap, sets the admin's role ID and secret ID, deletes role bootstrap,
#      in that order, and ends with `PASS: openbao-handover: done`;
#   3. no secret (the token, either ID) appears in any kubectl or bao argument, or in Ansible's output;
#   4. a store whose role bootstrap is gone passes with `already handed over` and sets nothing;
#   5. any other login failure fails the play with its HANDOVER line, and a pod that is not Ready stops it
#      before a token is made.
# Usage: .github/hosts-check/tests/test_openbao_handover.sh   (needs ansible-core)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
play=$root/hosts/ansible/playbooks/k8s-openbao-handover.yml
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

rid=0123456789abcdef0123456789abcdef0123456789abcdef
sid=fedcba9876543210fedcba9876543210fedcba9876543210
jwt=eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJlLXN0dWI
printf '%s' "$rid" > "$w/role-id"
printf '%s' "$sid" > "$w/secret-id"
mkdir -p "$w/bin" "$w/pod"

cat > "$w/bin/kubectl" <<EOF
#!/usr/bin/env bash
echo "kubectl \$*" >> "$w/args"
case "\$*" in
  *"get pod openbao-0"*) printf '%s' "\${READY:-true}" ;;
  *"create token openbao-bootstrap"*) printf '%s' "$jwt" ;;
  *"exec -i openbao-0 -c openbao -- sh -s"*) PATH="$w/pod:\$PATH" sh -s ;;
  *) echo "unexpected kubectl \$*" >&2; exit 3 ;;
esac
EOF
cat > "$w/pod/bao" <<EOF
#!/usr/bin/env bash
echo "bao \$*" >> "$w/args"
echo "bao \$*" >> "$w/calls"
case "\$*" in
  "write -field=token auth/kubernetes/login -")
    cat >> "$w/stdin"; echo >> "$w/stdin"
    case \${LOGIN:-ok} in
      ok) printf 'tok-secret-1' ;;
      gone) echo 'Error writing data to auth/kubernetes/login: * invalid role name "bootstrap"' >&2; exit 2 ;;
      *) echo 'Error writing data to auth/kubernetes/login: permission denied' >&2; exit 2 ;;
    esac ;;
  "write auth/approle/role/admin/role-id -"|"write auth/approle/role/admin/custom-secret-id -")
    [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4; cat >> "$w/stdin"; echo >> "$w/stdin" ;;
  "delete auth/kubernetes/role/bootstrap") [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4 ;;
  "token revoke -self") ;;
  *) echo "unexpected bao \$*" >&2; exit 3 ;;
esac
EOF
chmod +x "$w/bin/kubectl" "$w/pod/bao"

# The same play, aimed at the one test host.
sed 's/^  hosts: k8s_control_plane\[0\]$/  hosts: all/' "$play" > "$w/play.yml"
grep -q '^  hosts: all$' "$w/play.yml" || { echo "FAIL the play's hosts line changed"; exit 1; }
run() { # extra -e values...
  rm -f "$w/args" "$w/calls" "$w/stdin"
  (cd "$root/hosts/ansible" && PATH="$w/bin:$PATH" ANSIBLE_CONFIG=ansible.cfg ansible-playbook \
    -i "localhost," -e '{"ansible_connection":"local","ansible_become":false}' \
    -e "ansible_python_interpreter=$(command -v python3)" \
    -e k8s_gitops_source_openbao_in_cluster=true \
    -e "openbao_admin_role_id_file=$w/role-id" -e "openbao_admin_secret_id_file=$w/secret-id" \
    "$@" "$w/play.yml") > "$w/out" 2>&1
}
has() { grep -qF -- "$2" "$1"; }

run
if has "$w/out" "PASS: openbao-handover: skipped, no box address yet" && has "$w/out" "failed=0" && [ ! -s "$w/args" ]; then ok "with no box CIDR it hands nothing over and passes with a skip line"; else bad "no box CIDR was not a clean skip"; fi
for cidr in 127.0.0.1/32 192.0.2.7/24 0.0.0.0/32; do
  run -e k8s_gitops_source_openbao_box_cidr=$cidr
  if has "$w/out" "failed=1" && [ ! -s "$w/args" ]; then ok "refused with box CIDR $cidr, before any kubectl call"; else bad "box CIDR $cidr was not refused first"; fi
done
run -e k8s_gitops_source_openbao_box_cidr=192.0.2.7/32 -e k8s_gitops_source_openbao_in_cluster=false
if has "$w/out" "failed=1" && [ ! -s "$w/args" ]; then ok "refused with the in-cluster store off"; else bad "the in-cluster store off was not refused"; fi

run -e k8s_gitops_source_openbao_box_cidr=192.0.2.7/32
if has "$w/out" "PASS: openbao-handover: done"; then ok "a first hand-over ends with PASS ... done"; else bad "no PASS done line"; sed -n '1,60p' "$w/out"; fi
want=$'bao write -field=token auth/kubernetes/login -\nbao write auth/approle/role/admin/role-id -\nbao write auth/approle/role/admin/custom-secret-id -\nbao delete auth/kubernetes/role/bootstrap\nbao token revoke -self'
if [ "$(cat "$w/calls" 2>/dev/null)" = "$want" ]; then ok "login, role ID, secret ID, delete bootstrap, revoke: in that order"; else bad "calls: $(tr '\n' '|' < "$w/calls")"; fi
if has "$w/stdin" "\"role_id\":\"$rid\"" && has "$w/stdin" "\"secret_id\":\"$sid\"" && has "$w/stdin" "\"jwt\":\"$jwt\""; then ok "the token and both IDs reach bao on stdin"; else bad "stdin bodies wrong"; fi
leak=0
for s in "$rid" "$sid" "$jwt" tok-secret-1; do
  if has "$w/args" "$s" || has "$w/out" "$s"; then leak=1; fi
done
if [ $leak -eq 0 ]; then ok "no secret in any kubectl or bao argument, or in Ansible's output"; else bad "a secret leaked into arguments or output"; fi

LOGIN=gone run -e k8s_gitops_source_openbao_box_cidr=192.0.2.7/32
if has "$w/out" "PASS: openbao-handover: already handed over" && ! grep -q "role-id\|custom-secret-id\|delete" "$w/calls"; then ok "a store already handed over passes and sets nothing"; else bad "already-handed-over case wrong"; fi

LOGIN=denied run -e k8s_gitops_source_openbao_box_cidr=192.0.2.7/32
if has "$w/out" "failed=1" && has "$w/out" "HANDOVER: login as bootstrap failed" && ! has "$w/out" "PASS:"; then ok "another login failure fails with its HANDOVER line"; else bad "login failure not reported"; fi

READY=false run -e k8s_gitops_source_openbao_box_cidr=192.0.2.7/32
if has "$w/out" "failed=1" && ! grep -q "create token" "$w/args"; then ok "a pod that is not Ready stops it before a token is made"; else bad "not-Ready pod was not stopped"; fi

exit $fail
