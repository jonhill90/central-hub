#!/bin/sh
# Closes Home Assistant's first-run screen from inside the cluster, so nobody else can claim the owner account.
# Home Assistant's onboarding is open to anyone who reaches it until the `user` step is done; this Job does that step
# with a password made inside the cluster (never typed by a person) and finishes the steps that need a token.
# Every step is safe to repeat: once the user step is done the script prints PASS and exits.
set -eu
CID="$BASE/"
steps=$(curl -fsS --max-time 20 "$BASE/api/onboarding") || { echo "FAIL: onboarding endpoint did not answer"; exit 1; }
case $steps in
  *'"step": "user", "done": true'* | *'"step":"user","done":true'*) echo "PASS: onboarding user step already done"; exit 0 ;;
esac
body=$(printf '{"client_id":"%s","name":"%s","username":"%s","password":"%s","language":"%s"}' "$CID" "$OWNER_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$LANGUAGE")
resp=$(curl -fsS --max-time 30 -X POST -H 'Content-Type: application/json' -d "$body" "$BASE/api/onboarding/users") \
  || { echo "FAIL: creating the owner failed"; exit 1; }
code=$(printf '%s' "$resp" | sed -n 's/.*"auth_code": *"\([^"]*\)".*/\1/p')
[ -n "$code" ] || { echo "FAIL: no auth_code in the answer"; exit 1; }
tok=$(curl -fsS --max-time 20 -X POST --data-urlencode grant_type=authorization_code --data-urlencode "code=$code" \
  --data-urlencode "client_id=$CID" "$BASE/auth/token" | sed -n 's/.*"access_token": *"\([^"]*\)".*/\1/p')
[ -n "$tok" ] || { echo "FAIL: no access token for the owner"; exit 1; }
for step in core_config analytics; do
  curl -fsS --max-time 30 -X POST -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' -d '{}' \
    "$BASE/api/onboarding/$step" >/dev/null || echo "note: onboarding step $step did not complete; the owner can finish it in the UI"
done
after=$(curl -fsS --max-time 20 "$BASE/api/onboarding")
case $after in
  *'"step": "user", "done": true'* | *'"step":"user","done":true'*) echo "PASS: onboarding user step done by the setup job"; exit 0 ;;
esac
echo "FAIL: the user step is still open"; exit 1
