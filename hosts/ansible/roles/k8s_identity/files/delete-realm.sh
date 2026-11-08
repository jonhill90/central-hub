#!/usr/bin/env bash
# Delete one realm in Keycloak, run inside the Keycloak container: bash -s <realm> < delete-realm.sh
# Signs in to the master realm with the first admin account from the container's own environment
# (the operator sets it from Secret <name>-initial-admin), so no admin password leaves the pod.
# Prints "deleted" when it deleted the realm; a realm that isn't there is not an error.
set -euo pipefail
realm=$1
kcadm=/opt/keycloak/bin/kcadm.sh
config=$(mktemp)
trap 'rm -f "$config"' EXIT
"$kcadm" config credentials --config "$config" --server http://localhost:8080 --realm master \
  --user "${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN:-}}" \
  --password "${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}" >/dev/null
if "$kcadm" get "realms/$realm" --config "$config" >/dev/null 2>&1; then
  "$kcadm" delete "realms/$realm" --config "$config"
  echo deleted
fi
