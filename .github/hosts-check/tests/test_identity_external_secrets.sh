#!/usr/bin/env bash
# Role k8s_identity's secrets tasks (tasks/secrets.yml) with the apps' secrets store on and off (plan step 8a),
# against a stand-in kubectl that keeps the cluster's objects in a JSON file. Fake values only.
#   1. Store openbao: an ExternalSecret each for realm lab's Secret (every key the realm uses, from c1/identity) and
#      the three client secret copies (argocd-sso labelled part-of argocd), store openbao, creationPolicy Owner; none of
#      those four Secrets is made by the role; Jellyfin's lab root (a public certificate) still is.
#   2. A second run with the store on applies nothing.
#   3. Store off with an ExternalSecret of this role's left: the run stops before it makes any Secret.
#   4. Store off with none left: the role makes the four Secrets as before, and no ExternalSecret.
#   6. Store openbao on a cluster with no database account: the role makes none (no kubectl create of it); ExternalSecret sso-db reads
#      username and password from c1/identity-db through store openbao, Owner; store off makes it as before (case 4).
#   5. No value from the values file shows in the output or in an ExternalSecret.
#   6. Store openbao: Grafana is restarted once when grafana-sso's version is new to the role (and not while the Secret
#      isn't there yet), not again on a run with nothing new, and once more when its data changes, not when only its metadata does.
# Usage: .github/hosts-check/tests/test_identity_external_secrets.sh   (needs ansible-playbook with community.general)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin"
# kubectl: objects in $KUBE_STATE as {"<kind>/<ns>/<name>": manifest}; every call logged to $KUBE_LOG.
cat > "$t/bin/kubectl" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
st_file, log = os.environ["KUBE_STATE"], os.environ["KUBE_LOG"]
st = json.load(open(st_file)) if os.path.exists(st_file) else {}
ns = ""
if "-n" in a:
    i = a.index("-n"); ns = a[i + 1]; a = a[:i] + a[i + 2:]
# Only create and apply read stdin: in "delete ... && create -f -" the manifest is for create.
stdin = sys.stdin.read() if a[0] in ("create", "apply") else ""
open(log, "a").write(json.dumps({"args": a, "stdin": stdin}) + "\n")
def save(): json.dump(st, open(st_file, "w"))
if a[:2] == ["get", "namespace"]:
    print("namespace/" + a[2]); sys.exit(0)
if a[:2] == ["get", "externalsecrets"] and "-A" in a:
    for k in st:
        if k.startswith("ExternalSecret/"): print("externalsecret.external-secrets.io/" + k.split("/")[2])
    sys.exit(0)
if a[0] == "get" and a[1] == "secret" and any(".data" in x for x in a):
    obj = st.get(f"Secret/{ns}/{a[2]}")
    print(json.dumps(obj["data"], sort_keys=True) if obj else "", end=""); sys.exit(0)
if a[0] == "get" and a[1] in ("secret", "externalsecret"):
    kind = "Secret" if a[1] == "secret" else "ExternalSecret"
    obj = st.get(f"{kind}/{ns}/{a[2]}")
    if obj is None:
        sys.exit(0 if "--ignore-not-found" in a else 1)
    print(json.dumps(obj["metadata"].get("annotations", {}))); sys.exit(0)
if a[0] in ("create", "apply"):
    obj = json.loads(stdin)
    st[f"{obj['kind']}/{obj['metadata']['namespace']}/{obj['metadata']['name']}"] = obj; save()
    print("applied"); sys.exit(0)
if a[0] == "annotate":
    k, v = a[3].split("=", 1)
    st[f"ExternalSecret/{ns}/{a[2]}"]["metadata"].setdefault("annotations", {})[k] = v; save(); sys.exit(0)
if a[0] == "delete":
    st.pop(f"Secret/{ns}/{a[2]}", None); save(); sys.exit(0)
if a[0] in ("wait", "rollout"):
    sys.exit(0)
print("stand-in kubectl: unexpected " + " ".join(a), file=sys.stderr); sys.exit(3)
PY
chmod +x "$t/bin/kubectl"

printf '%s\n' 'GRAFANA_CLIENT_SECRET=gsecret1' 'ARGOCD_CLIENT_SECRET=asecret1' 'JELLYFIN_CLIENT_SECRET=jsecret1' \
  'PROXMOX_CLIENT_SECRET=psecret1' 'CENTRAL_HUB_APP_CLIENT_SECRET=csecret1' 'PASSWORD_OWNER=pwowner1' 'TOTP_OWNER=TOTPSEEDOWNER1' > "$t/identity.env"
chmod 0600 "$t/identity.env"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$t/ca.key" -subj /CN=lab-root -days 1 \
  -out "$t/ca.pem" 2>/dev/null
cat > "$t/play.yml" <<EOF
- hosts: localhost
  gather_facts: false
  vars:
    k8s_identity_zone: example.com
    k8s_identity_owner_username: owner
    # The default adds client openbao (openbao.<zone>) and its secret; this test is about the other clients' secrets.
    k8s_identity_openbao_client: false
    k8s_identity_values_file: $t/identity.env
    k8s_identity_jellyfin_root_ca_file: $t/ca.pem
  tasks:
    - ansible.builtin.include_role:
        name: k8s_identity
        tasks_from: secrets.yml
EOF
run() {
  : > "$t/log"
  (cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg PATH="$t/bin:$PATH" KUBE_STATE="$t/state.json" KUBE_LOG="$t/log" \
    ansible-playbook -i localhost, -c local "$t/play.yml" "$@" > "$t/out" 2>&1)
  rc=$?; out=$(cat "$t/out")
}
# fresh: a cluster that holds only the database account, which the role makes once on the node.
fresh() { echo '{"Secret/identity/sso-db": {"metadata": {"annotations": {}}}}' > "$t/state.json"; }
# what: kinds and names in the state, sorted, without the database account.
what() { python3 -I -c 'import json, sys; print(" ".join(sorted(k for k in json.load(open(sys.argv[1])) if k != "Secret/identity/sso-db")))' "$t/state.json"; }
applies() { grep -c '"args": \["apply"' "$t/log"; }
es() { python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]], sort_keys=True))' "$t/state.json" "$1"; }

# 1
fresh; run -e k8s_gitops_source_app_secrets_store=openbao; r1=$rc w1=$(what)
realm=$(es ExternalSecret/identity/realm-lab-secrets 2>/dev/null); argo=$(es ExternalSecret/argocd/argocd-sso 2>/dev/null)
realm_keys=$(python3 -I -c 'import json, sys; d = json.loads(sys.argv[1])["spec"]
print(d["secretStoreRef"]["name"], d["target"]["creationPolicy"],
      ",".join(sorted(e["secretKey"] + "=" + e["remoteRef"]["key"] + ":" + e["remoteRef"]["property"] for e in d["data"])))' "$realm" 2>/dev/null)
want_keys="openbao Owner ARGOCD_CLIENT_SECRET=c1/identity:ARGOCD_CLIENT_SECRET,CENTRAL_HUB_APP_CLIENT_SECRET=c1/identity:CENTRAL_HUB_APP_CLIENT_SECRET,GRAFANA_CLIENT_SECRET=c1/identity:GRAFANA_CLIENT_SECRET,JELLYFIN_CLIENT_SECRET=c1/identity:JELLYFIN_CLIENT_SECRET,OPNSENSE_CLIENT_SECRET=c1/identity:OPNSENSE_CLIENT_SECRET,PASSWORD_OWNER=c1/identity:PASSWORD_OWNER,PROXMOX_CLIENT_SECRET=c1/identity:PROXMOX_CLIENT_SECRET,TOTP_OWNER=c1/identity:TOTP_OWNER"
want_w1="ExternalSecret/argocd/argocd-sso ExternalSecret/central-hub-app/central-hub-app-sso ExternalSecret/identity/realm-lab-secrets ExternalSecret/identity/sso-bootstrap-admin ExternalSecret/identity/sso-db ExternalSecret/media/jellyfin-sso ExternalSecret/monitoring/grafana-sso Secret/central-hub-app/central-hub-app-oidc Secret/media/jellyfin-lab-root-ca"
if [[ $r1 -eq 0 && $w1 == "$want_w1" && $realm_keys == "$want_keys" &&
      $argo == *'"app.kubernetes.io/part-of": "argocd"'* && $argo == *'"property": "ARGOCD_CLIENT_SECRET"'* && $argo == *'"secretKey": "clientSecret"'* ]]; then
  ok "1. store openbao: seven ExternalSecrets (the database account from c1/identity-db, Keycloak's first admin from c1/identity-admin, the others from c1/identity), store openbao, Owner; only the lab root and the app's public names made as Secrets"
else bad "1. rc=$r1 [$w1] [$realm_keys] $argo $(tail -n 20 "$t/out")"; fi

# 2
run -e k8s_gitops_source_app_secrets_store=openbao; r2=$rc a2=$(applies)
if [[ $r2 -eq 0 && $a2 -eq 0 ]]; then ok "2. a second run with the store on applies nothing"
else bad "2. rc=$r2 applies=$a2"; fi

# 3
run; r3=$rc o3=$out c3=$(grep -c '"args": \["create"' "$t/log")
if [[ $r3 -ne 0 && $o3 == *"No ExternalSecret of this role's is left while the store is off"* && $c3 -eq 0 ]]; then
  ok "3. store off with an ExternalSecret left: stopped before any Secret is made"
else bad "3. rc=$r3 creates=$c3"; fi

# 4
fresh; run; r4=$rc w4=$(what)
want_w4="Secret/argocd/argocd-sso Secret/central-hub-app/central-hub-app-oidc Secret/central-hub-app/central-hub-app-sso Secret/identity/realm-lab-secrets Secret/media/jellyfin-lab-root-ca Secret/media/jellyfin-sso Secret/monitoring/grafana-sso"
if [[ $r4 -eq 0 && $w4 == "$want_w4" ]]; then ok "4. store off: the role makes the Secrets as before, no ExternalSecret"
else bad "4. rc=$r4 [$w4] $(tail -n 20 "$t/out")"; fi

# 5
fresh; run -e k8s_gitops_source_app_secrets_store=openbao
leaks=$(grep -cE 'gsecret1|asecret1|jsecret1|psecret1|csecret1|pwowner1|TOTPSEEDOWNER1' "$t/out" "$t/state.json" | awk -F: '{s += $2} END {print s}')
if [[ $rc -eq 0 && $leaks -eq 0 ]]; then ok "5. no value in the output or the ExternalSecrets"
else bad "5. rc=$rc, $leaks lines hold a value"; fi

# 6
rs() { grep -c '"args": \["rollout", "restart", "deployment/kube-prometheus-stack-grafana"\]' "$t/log"; }
setrv() { python3 -I -c 'import json, sys; f = sys.argv[1]; d = json.load(open(f)); d["Secret/monitoring/grafana-sso"] = {"metadata": {"resourceVersion": sys.argv[3]}, "data": {"client-secret": sys.argv[2]}}; json.dump(d, open(f, "w"))' "$t/state.json" "$1" "${2:-1}"; }
fresh; run -e k8s_gitops_source_app_secrets_store=openbao; n0=$(rs)
setrv b3JpZw== 11; run -e k8s_gitops_source_app_secrets_store=openbao; n1=$(rs)
run -e k8s_gitops_source_app_secrets_store=openbao; n2=$(rs)
setrv b3JpZw== 12; run -e k8s_gitops_source_app_secrets_store=openbao; n3=$(rs)   # metadata only: same data
setrv bmV3 13; run -e k8s_gitops_source_app_secrets_store=openbao; n4=$(rs)
if [[ $rc -eq 0 && $n0 -eq 0 && $n1 -eq 1 && $n2 -eq 0 && $n3 -eq 0 && $n4 -eq 1 ]]; then
  ok "6. openbao: Grafana restarts once per new grafana-sso data, never without one"
else bad "6. restarts: no secret $n0, new $n1, same $n2, metadata only $n3, data changed $n4, rc=$rc $(tail -n 15 "$t/out")"; fi

echo '{}' > "$t/state.json"; run -e k8s_gitops_source_app_secrets_store=openbao; r6=$rc
boot=$(es ExternalSecret/identity/sso-bootstrap-admin 2>/dev/null)
boot_keys=$(python3 -I -c 'import json, sys; d = json.loads(sys.argv[1])["spec"]
print(d["secretStoreRef"]["name"], d["target"]["creationPolicy"], d["target"]["name"],
      ",".join(sorted(e["secretKey"] + "=" + e["remoteRef"]["key"] + ":" + e["remoteRef"]["property"] for e in d["data"])))' "$boot" 2>/dev/null)
db_made=$(grep -c 'create secret generic sso-db' "$t/log")
db=$(es ExternalSecret/identity/sso-db 2>/dev/null)
db_keys=$(python3 -I -c 'import json, sys; d = json.loads(sys.argv[1])["spec"]
print(d["secretStoreRef"]["name"], d["target"]["creationPolicy"], d["target"]["name"],
      ",".join(sorted(e["secretKey"] + "=" + e["remoteRef"]["key"] + ":" + e["remoteRef"]["property"] for e in d["data"])))' "$db" 2>/dev/null)
if [[ $r6 -eq 0 && $db_made -eq 0 && $db_keys == "openbao Owner sso-db password=c1/identity-db:password,username=c1/identity-db:username" &&
      $boot_keys == "openbao Owner sso-bootstrap-admin password=c1/identity-admin:password,username=c1/identity-admin:username" ]]; then
  ok "7. store openbao: the database account and Keycloak's first admin are ExternalSecrets reading c1/identity-db and c1/identity-admin, and the role no longer makes the account"
else bad "7. rc=$r6 made=$db_made [$db_keys] $(tail -n 15 "$t/out")"; fi

exit "$fail"
