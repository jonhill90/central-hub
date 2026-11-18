#!/usr/bin/env bash
# Make sure one client is in a realm, without touching anything else in it. Run inside the Keycloak
# container: bash -s <realm> <clientId> < client.json
# The client's JSON comes on stdin. A client that isn't there is created; one that is there is updated
# from the JSON (kcadm merges the fields given), so a changed redirect or secret lands. Users, groups,
# other clients and sessions are not touched, which is why this exists: the realm replace path deletes
# the whole realm and ends every open sign-in.
# Signs in to the master realm with the first admin account from the container's own environment,
# as delete-realm.sh does. Prints "created" or "updated".
set -euo pipefail
realm=$1
client_id=$2
kcadm=/opt/keycloak/bin/kcadm.sh
config=$(mktemp)
body=$(mktemp)
trap 'rm -f "$config" "$body"' EXIT
cat > "$body"
grep -q "\"clientId\" *: *\"$client_id\"" "$body" || { echo "the JSON on stdin is not client $client_id" >&2; exit 1; }
for try in $(seq 1 60); do
  "$kcadm" config credentials --config "$config" --server http://localhost:8080 --realm master \
    --user "${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN:-}}" \
    --password "${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}" >/dev/null 2>&1 && break
  [ "$try" = 60 ] && { echo "could not sign in to Keycloak at localhost:8080" >&2; exit 1; }
  sleep 5
done
"$kcadm" get "realms/$realm" --config "$config" >/dev/null 2>&1 || { echo "realm $realm is not in Keycloak" >&2; exit 1; }
id=$("$kcadm" get clients -r "$realm" -q "clientId=$client_id" --fields id --format csv --noquotes --config "$config" | head -n1)
if [ -n "$id" ]; then
  "$kcadm" update "clients/$id" -r "$realm" -f "$body" --config "$config"
  echo updated
else
  "$kcadm" create clients -r "$realm" -f "$body" --config "$config" >/dev/null
  echo created
fi
