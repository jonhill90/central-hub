#!/bin/sh
# Jellyfin first-run setup (startup API, Jellyfin 12.2: StartupController and
# LibraryStructureController, both open to anonymous calls only until the wizard completes).
# Safe to run again: it stops as soon as the server says the wizard is done.
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

if api "$BASE/System/Info/Public" | grep -q '"StartupWizardCompleted":true'; then
  echo "wizard already completed: nothing to do"
  exit 0
fi

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
