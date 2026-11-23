#!/bin/sh
# Mealie's first account is made on first start with an e-mail and password the Mealie project publishes
# (docs.mealie.io, "Installation"), and its /api/auth/token accepts that password whatever ALLOW_PASSWORD_LOGIN says (that
# setting only hides the form: mealie/routes/app/app_about.py). So no pod of this app is reachable until this script has
# made that account's password the generated one in Secret <name>-admin, and proved the published one is refused.
# Safe to run again. It never prints a password: the new one is read from a file and sent from a file.
set -eu
umask 077
BASE="${BASE:?}"
# Wait for the pod to answer.
i=0
until curl -fsS -o /dev/null "$BASE/api/app/about"; do
  i=$((i + 1)); [ "$i" -lt 60 ] || { echo "mealie-admin: Mealie did not answer in 5 minutes" >&2; exit 1; }
  sleep 5
done
login() {   # prints the HTTP status; the token, if any, is left in /tmp/login.json
  curl -s -o /tmp/login.json -w '%{http_code}' -X POST "$BASE/api/auth/token" \
    --data-urlencode "username=$1" --data-urlencode "password@$2"
}
printf '%s' "$DEFAULT_PASSWORD" > /tmp/default-password
code=$(login "$DEFAULT_EMAIL" /tmp/default-password)
if [ "$code" = 200 ]; then
  token=$(sed -n 's/.*"access_token": *"\([^"]*\)".*/\1/p' /tmp/login.json)
  [ -n "$token" ] || { echo "mealie-admin: the published sign-in worked but no token came back" >&2; exit 1; }
  printf '{"currentPassword":"%s","newPassword":"%s"}' "$DEFAULT_PASSWORD" "$(cat /admin/password)" > /tmp/body.json
  code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$BASE/api/users/password" \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data @/tmp/body.json)
  [ "$code" = 200 ] || { echo "mealie-admin: changing the password answered HTTP $code" >&2; exit 1; }
  echo "mealie-admin: the account's published password was replaced"
fi
# The proof: the published password is refused, and the generated one works.
code=$(login "$DEFAULT_EMAIL" /tmp/default-password)
[ "$code" != 200 ] || { echo "mealie-admin: FAIL the published sign-in still works" >&2; exit 1; }
code=$(login "$DEFAULT_EMAIL" /admin/password)
[ "$code" = 200 ] || { echo "mealie-admin: FAIL the generated password is refused (HTTP $code): the account holds a password this chart did not set" >&2; exit 1; }
echo "mealie-admin: PASS the published sign-in is refused and the generated one works"
