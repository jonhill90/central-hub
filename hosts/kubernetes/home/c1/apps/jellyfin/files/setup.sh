#!/bin/sh
# Jellyfin first-run setup (startup API, Jellyfin 12.2: StartupController and
# LibraryStructureController, both open to anonymous calls only until the wizard completes).
# Safe to run again: the wizard runs only until the server says it is done; the metrics and sign-in
# steps after it write the same state every time.
# The password goes to curl on stdin, never on a command line or in the log. No heredocs:
# the root filesystem is read-only.
set -eu
api() { curl -fsS --retry 5 --retry-all-errors --retry-delay 3 -H 'Content-Type: application/json' "$@"; }

echo "waiting for $BASE/health"
i=0
until curl -fsS -o /dev/null "$BASE/health"; do
  i=$((i + 1)); [ "$i" -lt 90 ] || { echo "Jellyfin never became healthy" >&2; exit 1; }
  sleep 5
done

wizard() {
echo "1/4 server settings"
printf '{"ServerName":"%s","UICulture":"%s","MetadataCountryCode":"%s","PreferredMetadataLanguage":"%s"}' \
  "$SERVER_NAME" "$UI_CULTURE" "$COUNTRY" "$LANGUAGE" |
  api -X POST -o /dev/null --data-binary @- "$BASE/Startup/Configuration"

echo "2/4 first user"
api "$BASE/Startup/User" -o /dev/null
# 403 means a password is already set (an earlier run got this far); the same Secret set it.
code=$(printf '{"Name":"%s","Password":"%s"}' "$ADMIN_USER" "$ADMIN_PASSWORD" |
  curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    --data-binary @- "$BASE/Startup/User")
case $code in
  2??) echo "admin user set" ;;
  403) echo "admin password was already set by an earlier run" ;;
  *) echo "setting the admin user failed: HTTP $code" >&2; exit 1 ;;
esac

echo "3/4 media library"
if api "$BASE/Library/VirtualFolders" | grep -q "\"Name\":\"$LIBRARY_NAME\""; then
  echo "library $LIBRARY_NAME already there"
else
  api -X POST -o /dev/null --data '{"LibraryOptions":{}}' \
    "$BASE/Library/VirtualFolders?name=$LIBRARY_NAME&collectionType=$LIBRARY_TYPE&paths=$(echo "$LIBRARY_PATH" | sed 's|/|%2F|g')&refreshLibrary=true"
fi

echo "4/4 complete"
api -X POST -o /dev/null "$BASE/Startup/Complete"
api "$BASE/System/Info/Public" | grep -q '"StartupWizardCompleted":true'
echo "done: wizard completed, admin user $ADMIN_USER, library $LIBRARY_NAME at $LIBRARY_PATH"
}

if api "$BASE/System/Info/Public" | grep -q '"StartupWizardCompleted":true'; then
  echo "wizard already completed"
else
  wizard
fi

auth='Authorization: MediaBrowser Client="setup", Device="job", DeviceId="jellyfin-setup", Version="1"'
token=''
signin() {
  [ -z "$token" ] || return 0
  echo "sign in as $ADMIN_USER"
  token=$(printf '{"Username":"%s","Pw":"%s"}' "$ADMIN_USER" "$ADMIN_PASSWORD" |
    api -X POST -H "$auth" --data-binary @- "$BASE/Users/AuthenticateByName" |
    sed -n 's/.*"AccessToken":"\([^"]*\)".*/\1/p')
  [ -n "$token" ] || { echo "sign-in as $ADMIN_USER failed" >&2; exit 1; }
  authz="Authorization: MediaBrowser Client=\"setup\", Device=\"job\", DeviceId=\"jellyfin-setup\", Version=\"1\", Token=\"$token\""
}

# Prometheus metrics at /metrics (Jellyfin's EnableMetrics, off by default). Jellyfin reads the
# setting only when its web host starts (Jellyfin.Server/Startup.cs), so after turning it on the
# script asks Jellyfin to restart itself (POST /System/Restart), which builds the host again in the
# same process. Only the one setting changes: the rest of the configuration is posted back as read.
if [ "${METRICS_ENABLED:-false}" = "true" ]; then
  signin
  conf=$(api -H "$authz" "$BASE/System/Configuration")
  if printf '%s' "$conf" | grep -q '"EnableMetrics":true'; then
    echo "metrics: already on"
  else
    printf '%s' "$conf" | grep -q '"EnableMetrics":false' || { echo "metrics: EnableMetrics not in the configuration" >&2; exit 1; }
    echo "metrics: turning on, then restarting Jellyfin"
    printf '%s' "$conf" | sed 's/"EnableMetrics":false/"EnableMetrics":true/' |
      api -X POST -H "$authz" -o /dev/null --data-binary @- "$BASE/System/Configuration"
    api -X POST -H "$authz" -o /dev/null "$BASE/System/Restart"
    sleep 10
  fi
  i=0
  until curl -fsS -o /dev/null "$BASE/metrics"; do
    i=$((i + 1)); [ "$i" -lt 60 ] || { echo "metrics: $BASE/metrics never answered" >&2; exit 1; }
    sleep 5
  done
  echo "metrics: /metrics answers"
else
  echo "metrics: off, nothing to do"
fi

# Sign-in through Keycloak: write the SSO plugin's provider config (POST /sso/OID/Add/<provider>
# adds or overwrites it, so every run leaves the same state). Skipped when SSO is off or the client
# secret Secret does not exist yet. Neither the token nor the secret is printed.
[ "${SSO_ENABLED:-false}" = "true" ] || { echo "sso: off, nothing to do"; exit 0; }
[ -s /lab-ca/lab-root-ca.pem ] || { echo "sso: Secret $SSO_CA_NAME is missing, so Jellyfin can't trust Keycloak: skipped (cert-manager writes it once the lab CA is Ready; the next run retries)" >&2; exit 0; }
[ -n "${SSO_CLIENT_SECRET:-}" ] || { echo "sso: Secret $SSO_SECRET_NAME has no client-secret yet: skipped (run playbooks/k8s-identity.yml)" >&2; exit 0; }

echo "sso 1/3 sign in"
signin

echo "sso 2/3 plugin loaded?"
i=0
# The reply's key case and spacing are Jellyfin's to change (12.x may write "name" and add spaces), so match both.
until api -H "$authz" "$BASE/Plugins" | grep -Eiq '"name" *: *"SSO Authentication"'; do
  i=$((i + 1))
  if [ "$i" -ge 12 ]; then
    echo "sso: plugin SSO Authentication is not in GET /Plugins (see the Jellyfin log: targetAbi, meta.json); the reply listed these names:" >&2
    api -H "$authz" "$BASE/Plugins" | grep -Eio '"name" *: *"[^"]*"' >&2 || echo "(no names; the reply was empty or not JSON)" >&2
    exit 1
  fi
  sleep 5
done

echo "sso 3/3 provider $SSO_PROVIDER"
roles=$(printf '"%s",' $SSO_ROLES | sed 's/,$//')
admin_roles=$(printf '"%s",' $SSO_ADMIN_ROLES | sed 's/,$//')
printf '{"oidEndpoint":"%s","oidClientId":"%s","oidSecret":"%s","enabled":true,"enableAuthorization":true,"enableAllFolders":true,"roleClaim":"roles","roles":[%s],"adminRoles":[%s],"preserveAdminPermissions":true,"defaultUsernameClaim":"preferred_username","schemeOverride":"https"}' \
  "$SSO_ISSUER" "$SSO_CLIENT_ID" "$SSO_CLIENT_SECRET" "$roles" "$admin_roles" |
  api -X POST -H "$authz" -o /dev/null --data-binary @- "$BASE/sso/OID/Add/$SSO_PROVIDER"
api -H "$authz" "$BASE/sso/OID/Get" | grep -q "\"$SSO_PROVIDER\"" || { echo "sso: provider $SSO_PROVIDER not listed after the write" >&2; exit 1; }
echo "done: sso provider $SSO_PROVIDER set, issuer $SSO_ISSUER"
