#!/usr/bin/env bash
# Set a live realm's display name to the template's value, without touching anything else in the realm. Run inside the
# Keycloak container: bash -c "$(cat this)" ensure-realm-display-name <realm> <display name>
# The realm import never changes a live realm (docs/runbooks/set-up-lab-sign-in.md, "Change the button name"), so a renamed
# template needs this one step. Signs in as ensure-client.sh does: the first admin account from the container's
# environment, and when Keycloak refuses it, the recovery admin c1-admin with the same password. Prints "unchanged" or
# "updated", or one line "ensure-realm-display-name: <step> failed: <reason>" (a fixed phrase, never kcadm's text).
set -euo pipefail
realm=$1
name=$2
kcadm=${KCADM:-/opt/keycloak/bin/kcadm.sh}
config=$(mktemp)
err=$(mktemp)
trap 'rm -f "$config" "$err"' EXIT
fail() {
  local why=unclassified
  for pair in "nvalid user credentials:refused (wrong username or password)" "invalid_grant:refused (wrong username or password)" \
              "not found:not found" "orbidden:forbidden" "nauthorized:unauthorized" "efused:connection refused"; do
    if grep -q "${pair%%:*}" "$err" 2>/dev/null; then why=${pair#*:}; break; fi
  done
  echo "ensure-realm-display-name: $1 failed: $why"
  exit 1
}
user=${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN:-}}
recovery=${KC_RECOVERY_ADMIN_USERNAME:-c1-admin}
for try in $(seq 1 60); do
  "$kcadm" config credentials --config "$config" --server http://localhost:8080 --realm master \
    --user "$user" \
    --password "${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}" >/dev/null 2>"$err" && break
  if grep -q -e "nvalid user credentials" -e "invalid_grant" "$err"; then
    [ "$user" != "$recovery" ] && { user=$recovery; continue; }
    fail "admin sign-in"
  fi
  [ "$try" = 60 ] && fail "admin sign-in"
  sleep 5
done
current=$("$kcadm" get "realms/$realm" --fields displayName --format csv --noquotes --config "$config" 2>"$err") || fail "realm lookup"
if [ "$current" = "$name" ]; then
  echo unchanged
else
  "$kcadm" update "realms/$realm" -s "displayName=$name" --config "$config" >/dev/null 2>"$err" || fail "update"
  echo updated
fi
