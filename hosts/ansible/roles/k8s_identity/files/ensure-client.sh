#!/usr/bin/env bash
# Make sure one client is in a realm, without touching anything else in it. Run inside the Keycloak
# container: bash -s <realm> <clientId> < client.json
# The client's JSON comes on stdin. A client that isn't there is created; one that is there is updated
# from the JSON (kcadm merges the fields given), so a changed redirect or secret lands. Users, groups,
# other clients and sessions are not touched, which is why this exists: the realm replace path deletes
# the whole realm and ends every open sign-in.
# Signs in to the master realm with the first admin account from the container's own environment,
# as delete-realm.sh does. Prints "created" or "updated". When a step fails it prints one line,
# "ensure-client: <step> failed: <reason>", the reason a fixed phrase picked from kcadm's own error
# text, never the text itself (it can hold the JSON, which holds client secrets); the exit code is 1.
set -euo pipefail
realm=$1
client_id=$2
kcadm=${KCADM:-/opt/keycloak/bin/kcadm.sh}
config=$(mktemp)
body=$(mktemp)
err=$(mktemp)
trap 'rm -f "$config" "$body" "$err"' EXIT
# A step's own error text goes to a file; what is printed is a fixed phrase for it.
fail() {
  local step=$1 rc=$2 why=unclassified
  for pair in "already exists:already exists" "onflict:conflict" "not found:not found" "orbidden:forbidden" \
              "nauthorized:unauthorized" "nvalid:invalid input" "Bad Request:bad request" "nrecognized:unrecognized field" \
              "efused:connection refused" "Unable to:kcadm could not run it"; do
    if grep -q "${pair%%:*}" "$err" 2>/dev/null; then why=${pair#*:}; break; fi
  done
  echo "ensure-client: $step failed: $why (kcadm exit $rc, $(wc -c < "$err" | tr -d ' ') bytes of error text)"
  exit 1
}
cat > "$body"
grep -q "\"clientId\" *: *\"$client_id\"" "$body" || { echo "the JSON on stdin is not client $client_id" >&2; exit 1; }
for try in $(seq 1 60); do
  "$kcadm" config credentials --config "$config" --server http://localhost:8080 --realm master \
    --user "${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN:-}}" \
    --password "${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}" >/dev/null 2>"$err" && break
  [ "$try" = 60 ] && { echo "could not sign in to Keycloak at localhost:8080" >&2; fail "admin sign-in" 1; }
  sleep 5
done
"$kcadm" get "realms/$realm" --config "$config" >/dev/null 2>"$err" || fail "realm lookup" $?
# No pipe into head: with pipefail a reader that quits early can fail the step for no reason.
found=$("$kcadm" get clients -r "$realm" -q "clientId=$client_id" --fields id --format csv --noquotes --config "$config" 2>"$err") \
  || fail "client lookup" $?
id=${found%%$'\n'*}
if [ -n "$id" ]; then
  "$kcadm" update "clients/$id" -r "$realm" -f "$body" --config "$config" >/dev/null 2>"$err" || fail "update" $?
  echo updated
else
  "$kcadm" create clients -r "$realm" -f "$body" --config "$config" >/dev/null 2>"$err" || fail "create" $?
  echo created
fi
