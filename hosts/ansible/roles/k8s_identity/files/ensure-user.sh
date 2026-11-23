#!/usr/bin/env bash
# Make sure one user is in a realm, without touching anything else in it. Run inside the Keycloak
# container: bash -s <realm> <username> < user.json
# The user's JSON comes on stdin (files/user-json.py). A user that isn't there is created, with its groups,
# its password and, for an admin, its TOTP credential. A user that is there is left exactly as it is, passwords
# and seeds included: a changed password or seed is the realm replace's job, or a delete, which is the
# owner's go. Other users, groups, clients and sessions are not touched, which is why this exists: the realm
# replace path deletes the whole realm and ends every open sign-in.
# Signs in to the master realm with the first admin account from the container's own environment, as
# ensure-client.sh does. Prints "created" or "exists".
set -euo pipefail
realm=$1
username=$2
kcadm=${KCADM:-/opt/keycloak/bin/kcadm.sh}
config=$(mktemp)
body=$(mktemp)
trap 'rm -f "$config" "$body"' EXIT
cat > "$body"
grep -q "\"username\" *: *\"$username\"" "$body" || { echo "the JSON on stdin is not user $username" >&2; exit 1; }
# The first admin account from the container's environment; when Keycloak refuses it (invalid_grant), the recovery admin
# c1-admin with the same password (made by `c1-ansible apply identity-admin-recover`), as ensure-client.sh does.
user=${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN:-}}
recovery=${KC_RECOVERY_ADMIN_USERNAME:-c1-admin}
errf=$(mktemp)
trap 'rm -f "$config" "$body" "$errf"' EXIT
for try in $(seq 1 60); do
  "$kcadm" config credentials --config "$config" --server http://localhost:8080 --realm master \
    --user "$user" \
    --password "${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}" >/dev/null 2>"$errf" && break
  if grep -q -e "nvalid user credentials" -e "invalid_grant" "$errf"; then
    [ "$user" != "$recovery" ] && { user=$recovery; continue; }
    echo "admin sign-in refused (invalid_grant: wrong username or password, or a disabled or locked account)" >&2; exit 1
  fi
  [ "$try" = 60 ] && { echo "could not sign in to Keycloak at localhost:8080" >&2; exit 1; }
  sleep 5
done
"$kcadm" get "realms/$realm" --config "$config" >/dev/null 2>&1 || { echo "realm $realm is not in Keycloak" >&2; exit 1; }
id=$("$kcadm" get users -r "$realm" -q "username=$username" -q exact=true --fields id --format csv --noquotes --config "$config" | head -n1)
if [ -n "$id" ]; then
  echo exists
else
  "$kcadm" create users -r "$realm" -f "$body" --config "$config" >/dev/null
  echo created
fi
