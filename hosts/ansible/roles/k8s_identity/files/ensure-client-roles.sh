#!/usr/bin/env bash
# Make sure a client's roles exist and the named groups hold them, in a live realm, without touching anything else in it.
# Run inside the Keycloak container: bash -c <this file> ensure-client-roles <realm> <clientId> <roles, comma separated> <group:role,role;group:role>
# The realm import that carries these roles never runs on a live realm (it only makes a realm that is missing), so this does the
# same in place: a role that is there is left alone, a group that already holds a role is not changed. Same sign-in and error style
# as ensure-client.sh: one line "ensure-client-roles: <step> failed: <reason>" and exit 1; prints "roles ok: <n> created, <m> mapped".
set -euo pipefail
realm=$1
client_id=$2
roles=$3
pairs=${4:-}
kcadm=${KCADM:-/opt/keycloak/bin/kcadm.sh}
config=$(mktemp)
err=$(mktemp)
trap 'rm -f "$config" "$err"' EXIT
fail() { echo "ensure-client-roles: $1 failed (kcadm exit $2, $(wc -c < "$err" | tr -d ' ') bytes of error text)"; exit 1; }
user=${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN:-}}
recovery=${KC_RECOVERY_ADMIN_USERNAME:-c1-admin}
for try in $(seq 1 60); do
  "$kcadm" config credentials --config "$config" --server http://localhost:8080 --realm master \
    --user "$user" \
    --password "${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}" >/dev/null 2>"$err" && break
  if grep -q -e "nvalid user credentials" -e "invalid_grant" "$err"; then
    [ "$user" != "$recovery" ] && { user=$recovery; continue; }
    fail "admin sign-in" 1
  fi
  [ "$try" = 60 ] && fail "admin sign-in" 1
  sleep 5
done
found=$("$kcadm" get clients -r "$realm" -q "clientId=$client_id" --fields id --format csv --noquotes --config "$config" 2>"$err") \
  || fail "client lookup" $?
id=${found%%$'\n'*}
[ -n "$id" ] || { echo "ensure-client-roles: client lookup failed: client $client_id is not in realm $realm"; exit 1; }
created=0 mapped=0
IFS=, read -r -a role_list <<< "$roles"
for role in "${role_list[@]}"; do
  if "$kcadm" get "clients/$id/roles/$role" -r "$realm" --config "$config" >/dev/null 2>"$err"; then continue; fi
  "$kcadm" create "clients/$id/roles" -r "$realm" -s "name=$role" --config "$config" >/dev/null 2>"$err" || fail "create role $role" $?
  created=$((created + 1))
done
IFS=';' read -r -a pair_list <<< "$pairs"
for pair in "${pair_list[@]}"; do
  [ -n "$pair" ] || continue
  group=${pair%%:*}
  IFS=, read -r -a want <<< "${pair#*:}"
  have=$("$kcadm" get "groups" -r "$realm" -q "search=$group" --fields id --format csv --noquotes --config "$config" 2>"$err") || fail "group lookup" $?
  [ -n "$have" ] || { echo "ensure-client-roles: group lookup failed: group $group is not in realm $realm"; exit 1; }
  args=()
  for role in "${want[@]}"; do args+=(--rolename "$role"); done
  "$kcadm" add-roles -r "$realm" --gname "$group" --cclientid "$client_id" "${args[@]}" --config "$config" >/dev/null 2>"$err" || fail "map roles to group $group" $?
  mapped=$((mapped + 1))
done
echo "roles ok: $created created, $mapped mapped"
