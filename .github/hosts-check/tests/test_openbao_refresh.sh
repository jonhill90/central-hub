#!/usr/bin/env bash
# playbooks/k8s-openbao-refresh.yml offline, against a stub kubectl whose `exec ... sh -s` runs the play's in-pod
# script here with a stub `bao` that keeps its policies and role admin in files:
#   1. no box CIDR, a loopback or wider one, an env other than dev or prod, or the in-cluster store off fail it before
#      any kubectl call;
#   2. a store whose snapshot policy reads dev's mark gets prod's from ConfigMap openbao-policies, and only that policy
#      is written; role admin is bound to the box's /32; it signs in, reads, writes, binds, reads back and revokes, in
#      that order, and ends with `PASS: openbao-refresh: policies changed: snapshot`;
#   3. no secret (the token, either ID) appears in any kubectl or bao argument, or in Ansible's output;
#   4. a second run over the same policies writes none and says `policies changed: none`;
#   5. a ConfigMap whose snapshot policy reads another env's mark, or lacks a policy, stops it before the exec;
#   6. a refused admin login fails with its REFRESH line and writes nothing; a role that reads back other bindings or
#      other policies fails with a FAIL line; a pod that is not Ready stops it before the ConfigMap is read.
# Usage: .github/hosts-check/tests/test_openbao_refresh.sh   (needs ansible-core)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
play=$root/hosts/ansible/playbooks/k8s-openbao-refresh.yml
pol=$root/hosts/kubernetes/home/c1/apps/openbao-store/policies
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

rid=0123456789abcdef0123456789abcdef0123456789abcdef
sid=fedcba9876543210fedcba9876543210fedcba9876543210
cidr=192.0.2.7/32
printf '%s' "$rid" > "$w/role-id"
printf '%s' "$sid" > "$w/secret-id"
mkdir -p "$w/bin" "$w/pod" "$w/store"

# ConfigMap openbao-policies as Argo CD renders it: the four files, snapshot.hcl with markEnv filled in.
cm() { # env [leave-out]
  python3 -I - "$pol" "$1" "${2:-}" > "$w/cm.json" <<'PY'
import json, os, sys
d, env, leave = sys.argv[1:4]
data = {}
for n in ("admin", "bootstrap", "eso-c1", "snapshot"):
    if n == leave: continue
    data[n + ".hcl"] = open(os.path.join(d, n + ".hcl")).read().replace("{{ .Values.markEnv }}", env)
print(json.dumps({"kind": "ConfigMap", "data": data}))
PY
}
# The store as prod's self-init left it: the same policies, but the snapshot policy for dev's mark.
fresh_store() {
  rm -f "$w/store/"*
  for n in admin bootstrap eso-c1 snapshot; do
    python3 -I -c 'import sys; t = open(sys.argv[1]).read().replace("{{ .Values.markEnv }}", "dev"); print(t, end="")' "$pol/$n.hcl" > "$w/store/$n"
  done
  printf '%s' '127.0.0.1/32' > "$w/store/role-cidr"
}

cat > "$w/bin/kubectl" <<EOF
#!/usr/bin/env bash
echo "kubectl \$*" >> "$w/args"
case "\$*" in
  *"get pod openbao-0"*) printf '%s' "\${READY:-true}" ;;
  *"get configmap openbao-policies -o json"*) cat "$w/cm.json" ;;
  *"exec -i openbao-0 -c openbao -- sh -s"*) PATH="$w/pod:\$PATH" sh -s ;;
  *) echo "unexpected kubectl \$*" >&2; exit 3 ;;
esac
EOF
cat > "$w/pod/bao" <<EOF
#!/usr/bin/env bash
echo "bao \$*" >> "$w/args"
echo "bao \$*" >> "$w/calls"
[ "\$BAO_ADDR" = https://127.0.0.1:8200 ] && [ "\$BAO_TLS_SERVER_NAME" = openbao.openbao.svc ] || { echo "wrong address" >&2; exit 5; }
case "\$*" in
  "write -field=token auth/approle/login -")
    cat >> "$w/stdin"; echo >> "$w/stdin"
    case \${LOGIN:-ok} in
      ok) printf 'tok-secret-1' ;;
      *) echo 'Error writing data to auth/approle/login: Code: 400. Errors: * source address "127.0.0.1" unauthorized by CIDR restrictions on the role' >&2; exit 2 ;;
    esac ;;
  "policy read "*) [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4; [ -f "$w/store/\$3" ] || exit 2; cat "$w/store/\$3"; echo ;;
  "policy write "*" -") [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4; cat > "$w/store/\$3" ;;
  "write auth/approle/role/admin secret_id_bound_cidrs=$cidr token_bound_cidrs=$cidr")
    [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4; printf '%s' "$cidr" > "$w/store/role-cidr" ;;
  "read -format=json auth/approle/role/admin")
    [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4
    c=\$(cat "$w/store/role-cidr"); p=admin
    [ "\${ROLE:-ok}" = ok ] || p=default
    printf '{\n  "data": {\n    "secret_id_bound_cidrs": ["%s"],\n    "token_bound_cidrs": ["%s"],\n    "token_policies": ["%s"],\n    "token_ttl": 900\n  }\n}\n' "\$c" "\$c" "\$p" ;;
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
writes() { grep -c "policy write\|write auth/approle/role/admin " "$w/calls" 2>/dev/null || true; }

cm prod; fresh_store
for bad_args in "-e openbao_refresh_env=prod" "-e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=127.0.0.1/32" \
  "-e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=192.0.2.7/24" "-e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=0.0.0.0/32" \
  "-e openbao_refresh_env=staging -e k8s_gitops_source_openbao_box_cidr=$cidr" "-e k8s_gitops_source_openbao_box_cidr=$cidr" \
  "-e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr -e k8s_gitops_source_openbao_in_cluster=false"; do
  # shellcheck disable=SC2086  # the -e pairs split on purpose
  run $bad_args
  if has "$w/out" "failed=1" && [ ! -s "$w/args" ]; then ok "1. refused before any kubectl call: $bad_args"; else bad "1. not refused first: $bad_args"; fi
done

cm prod; fresh_store
run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "PASS: openbao-refresh: policies changed: snapshot; role admin bound to the box's /32"; then ok "2. a first run ends with PASS, policies changed: snapshot"; else bad "2. no PASS line"; sed -n '1,80p' "$w/out"; fi
if grep -qF 'path "kv/data/prod/snapshot-mark"' "$w/store/snapshot" && ! grep -qF 'kv/data/dev/' "$w/store/snapshot" &&
  [ "$(cat "$w/store/role-cidr")" = "$cidr" ]; then ok "2. the snapshot policy now reads prod's mark, and role admin is bound to the box's /32"; else bad "2. store not refreshed"; fi
want=$'bao write -field=token auth/approle/login -\nbao policy read admin\nbao policy read bootstrap\nbao policy read eso-c1\nbao policy read snapshot\nbao policy write snapshot -\nbao policy read snapshot\nbao write auth/approle/role/admin secret_id_bound_cidrs='"$cidr"' token_bound_cidrs='"$cidr"$'\nbao read -format=json auth/approle/role/admin\nbao token revoke -self'
if [ "$(cat "$w/calls" 2>/dev/null)" = "$want" ]; then ok "2. login, reads, one write, read-back, bind, role read, revoke: in that order"; else bad "2. calls: $(tr '\n' '|' < "$w/calls")"; fi
if has "$w/stdin" "\"role_id\":\"$rid\"" && has "$w/stdin" "\"secret_id\":\"$sid\""; then ok "3. both IDs reach bao on stdin"; else bad "3. stdin body wrong"; fi
leak=0
for s in "$rid" "$sid" tok-secret-1; do
  if has "$w/args" "$s" || has "$w/out" "$s"; then leak=1; fi
done
if [ $leak -eq 0 ]; then ok "3. no secret in any kubectl or bao argument, or in Ansible's output"; else bad "3. a secret leaked into arguments or output"; fi

run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "PASS: openbao-refresh: policies changed: none" && ! grep -q "policy write" "$w/calls"; then ok "4. a second run over the same policies writes none"; else bad "4. second run wrote or failed"; fi

cm dev; fresh_store
run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && ! grep -q "exec" "$w/args"; then ok "5. a ConfigMap with another env's mark stops it before the exec"; else bad "5. other env's mark not refused"; fi
cm prod bootstrap
run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && ! grep -q "exec" "$w/args"; then ok "5. a ConfigMap missing a policy stops it before the exec"; else bad "5. missing policy not refused"; fi

cm prod; fresh_store
LOGIN=denied run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && has "$w/out" "REFRESH: admin login from inside the pod failed" && [ "$(writes)" = 0 ]; then ok "6. a refused admin login fails with its REFRESH line and writes nothing"; else bad "6. refused login not reported"; fi
fresh_store
ROLE=other run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && has "$w/out" "FAIL: openbao-refresh: role admin reads back"; then ok "6. a role that reads back other policies fails with a FAIL line"; else bad "6. bad role read-back passed"; fi
fresh_store
READY=false run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && ! grep -q "configmap\|exec" "$w/args"; then ok "6. a pod that is not Ready stops it before the ConfigMap is read"; else bad "6. not-Ready pod was not stopped"; fi

exit $fail
