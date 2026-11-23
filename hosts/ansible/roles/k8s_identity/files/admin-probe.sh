#!/usr/bin/env bash
# Can the Keycloak admin accounts sign in? Run inside the Keycloak container: bash -s < admin-probe.sh
# Tries, once each, the first admin account from the container's environment and the recovery admin (c1-admin) with the same
# password, and prints "admin-probe: env-user ok|refused|error" and "admin-probe: recovery-user ok|refused|error". It prints
# no name, password or Keycloak text, only a count of bytes for an unclassified error. It changes nothing in Keycloak.
set -uo pipefail
kcadm=${KCADM:-/opt/keycloak/bin/kcadm.sh}
cfg=$(mktemp)
err=$(mktemp)
trap 'rm -f "$cfg" "$err"' EXIT
pw=${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}
try() {
  if "$kcadm" config credentials --config "$cfg" --server http://localhost:8080 --realm master --user "$2" --password "$pw" >/dev/null 2>"$err"; then
    echo "admin-probe: $1 ok"
  elif grep -q -e "nvalid user credentials" -e "invalid_grant" "$err"; then
    echo "admin-probe: $1 refused"
  else
    echo "admin-probe: $1 error ($(wc -c < "$err" | tr -d ' ') bytes of error text)"
  fi
}
try env-user "${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN:-}}"
try recovery-user "${KC_RECOVERY_ADMIN_USERNAME:-c1-admin}"
