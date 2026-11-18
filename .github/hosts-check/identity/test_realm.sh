#!/usr/bin/env bash
# Import realm lab into a real Keycloak and check what lab apps will get from it (STD-0005 level 3).
# Runs Keycloak in one container with the settings the operator gives it on c1 (hostname, plain
# HTTP behind a proxy, X-Forwarded headers), imports the rendered realm, then checks with Keycloak's
# own admin tool: every client and redirect, each user's password, the groups and roles claims in
# an ID token for each app, and the role's replace path (delete the realm, import it again).
# Usage: test_realm.sh <rendered realm.yaml> [<theme folder>]   Needs: docker, python3 with PyYAML.
# With a theme folder, it is mounted as the role mounts k8s_identity_theme_dir, and the realm's sign-in
# page must load that theme's stylesheet.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
realm_yaml=$1
theme=${2:-}

# The same Keycloak release the operator runs (k8s_identity_version), pinned by digest: the 26.8.1
# image published 2026-10-23, the newest build of it at least two weeks old (STD-0003 rule 1).
image=quay.io/keycloak/keycloak@sha256:a78d6b79572168cb25886b80a8b5b8d4ed4390743e3eecb810538683e209dd6b
name=central-hub-realm-test-$$
host=https://sso.example.com
work=$(mktemp -d)
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

python3 -I "$here/realm_to_json.py" "$realm_yaml" "$work/lab.json"
chmod 0644 "$work/lab.json"
chmod 0755 "$work"

# start-dev keeps its data in memory-backed H2; --import-realm reads /opt/keycloak/data/import.
theme_args=()
[ -n "$theme" ] && theme_args=(-v "$theme:/opt/keycloak/themes/$(basename "$theme"):ro")
docker run -d --name "$name" \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=test-admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=test-admin \
  -v "$work:/opt/keycloak/data/import:ro" "${theme_args[@]}" \
  "$image" start-dev --import-realm --health-enabled=true \
  --hostname="$host" --http-enabled=true --proxy-headers=xforwarded >/dev/null

for _ in $(seq 1 90); do
  if docker exec "$name" bash -c 'exec 3<>/dev/tcp/localhost/9000 && printf "GET /health/ready HTTP/1.0\r\n\r\n" >&3 && grep -q "\"UP\"" <&3' 2>/dev/null; then
    ready=1; break
  fi
  sleep 2
done
if [ -z "${ready:-}" ]; then
  docker logs "$name" | tail -40 >&2
  echo "FAIL: Keycloak did not become ready" >&2
  exit 1
fi

kc() { docker exec "$name" /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config; }
kc config credentials --server http://localhost:8080 --realm master --user test-admin --password test-admin >/dev/null

# The checks, in Python on this side; the container only answers kcadm calls.
export name
# The checks run three times in this one Keycloak; Keycloak refuses a TOTP code it already took, so the runs share the last time step used.
OTP_STEP_FILE=$work/otp-step
export OTP_STEP_FILE
python3 -I "$here/check_realm.py" "$work/lab.json"

# The replace path the role takes when the realm changes: the role's own delete script, inside the
# container as on c1, then the same file imported again (the operator imports with kc.sh import;
# the admin API takes the same JSON).
out=$(docker exec -i "$name" bash -s lab < "$root/hosts/ansible/roles/k8s_identity/files/delete-realm.sh")
[ "$out" = deleted ] || { echo "FAIL: delete-realm.sh printed '$out', not 'deleted'" >&2; exit 1; }
out=$(docker exec -i "$name" bash -s lab < "$root/hosts/ansible/roles/k8s_identity/files/delete-realm.sh")
[ -z "$out" ] || { echo "FAIL: delete-realm.sh on a missing realm printed '$out'" >&2; exit 1; }
docker cp "$work/lab.json" "$name:/tmp/lab.json"
kc create realms -f /tmp/lab.json
python3 -I "$here/check_realm.py" "$work/lab.json"
echo "identity: realm imported, checked, deleted, imported again and checked"

# The add-a-client path the role takes to put a client in the live realm without the replace (role
# tasks/clients.yml): files/client-json.py fills the client's secret from the environment and
# files/ensure-client.sh creates or updates it inside the container. Delete the client first so the
# create path runs, then run it again for the update path, with a changed redirect, and check that
# the other clients and the users are still there and untouched.
roledir="$root/hosts/ansible/roles/k8s_identity/files"
ensure() { # <clientId> <json file>
  docker exec -i "$name" bash -c "$(cat "$roledir/ensure-client.sh")" ensure-client lab "$1" < "$2"
}
client=jellyfin
JELLYFIN_CLIENT_SECRET=test-JELLYFIN_CLIENT_SECRET python3 -I "$roledir/client-json.py" "$realm_yaml" "$client" > "$work/client.json"
before=$(kc get users -r lab --fields username --format csv --noquotes | sort | tr '\n' ' ')
others=$(kc get clients -r lab --fields clientId --format csv --noquotes | grep -v "^$client$" | sort | tr '\n' ' ')
id=$(kc get clients -r lab -q "clientId=$client" --fields id --format csv --noquotes)
kc delete "clients/$id" -r lab
out=$(ensure "$client" "$work/client.json")
[ "$out" = created ] || { echo "FAIL: ensure-client.sh printed '$out' for a missing client, not 'created'" >&2; exit 1; }
out=$(ensure "$client" "$work/client.json")
[ "$out" = updated ] || { echo "FAIL: ensure-client.sh printed '$out' for an existing client, not 'updated'" >&2; exit 1; }
python3 -I - "$work/client.json" > "$work/client-changed.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["redirectUris"] = c["redirectUris"] + ["https://changed.example.com/sso/OID/redirect/keycloak"]
print(json.dumps(c))
PY
out=$(ensure "$client" "$work/client-changed.json")
[ "$out" = updated ] || { echo "FAIL: ensure-client.sh printed '$out' for a changed client, not 'updated'" >&2; exit 1; }
# Read the whole answer first: with pipefail, `grep -q` closing the pipe at its first match can make kcadm
# die of SIGPIPE, and the pipeline then fails even though the redirect is there.
redirects=$(kc get clients -r lab -q "clientId=$client" --fields redirectUris)
case $redirects in
  *changed.example.com*) ;;
  *) echo "FAIL: the changed redirect did not land; kcadm answered: $redirects" >&2; exit 1 ;;
esac
out=$(ensure "$client" "$work/client.json")
after=$(kc get users -r lab --fields username --format csv --noquotes | sort | tr '\n' ' ')
others_after=$(kc get clients -r lab --fields clientId --format csv --noquotes | grep -v "^$client$" | sort | tr '\n' ' ')
[ "$before" = "$after" ] || { echo "FAIL: users changed: '$before' became '$after'" >&2; exit 1; }
[ "$others" = "$others_after" ] || { echo "FAIL: other clients changed" >&2; exit 1; }
if echo '{"clientId":"other"}' | ensure "$client" /dev/stdin 2>/dev/null; then
  echo "FAIL: ensure-client.sh took JSON for another client" >&2; exit 1
fi
python3 -I "$here/check_realm.py" "$work/lab.json"
echo "identity: a client deleted, added and updated through ensure-client.sh; users and other clients untouched; realm checked again"

# The sign-in page uses the theme: Argo CD's client (no PKCE needed) asks for the page, and the page
# links the theme's stylesheet, which Keycloak serves.
if [ -n "$theme" ]; then
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")
  python3 -I "$here/check_theme.py" "http://$ip:8080" "$(basename "$theme")"
fi
