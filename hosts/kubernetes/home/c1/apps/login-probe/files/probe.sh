#!/bin/sh
# Sign-in checks from inside c1, no password. The log prints no host name, URL or secret: only check names and codes. Prints one PASS or FAIL line per check and a last RESULT
# line, and exits 1 if any check failed. Reads only; the Job has no Kubernetes credential. No heredocs: the root filesystem is
# read-only.
set -u
fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }
code() { curl -sS -o /dev/null -m 20 -w '%{http_code}' "$@" 2>/dev/null || echo 000; }

# Where a redirect goes, with the scheme, host, query and fragment dropped, so the log shows the path and no host name.
where() { printf '%s' "$1" | sed 's#^[A-Za-z]*://[^/]*##; s#^//[^/]*##; s#[?].*##; s|#.*||'; }
hdrs() { curl -sS -o /dev/null -m 20 -D - "$1" 2>/dev/null | tr -d '\r'; }
scode() { printf '%s\n' "$1" | sed -n '1s/^HTTP[^ ]* \([0-9]*\).*/\1/p'; }
sloc() { printf '%s\n' "$1" | sed -n 's/^[Ll]ocation: *//p' | head -1; }

auth="$KEYCLOAK/realms/$REALM/protocol/openid-connect/auth"

echo "keycloak discovery"
disc=$(curl -sS -m 20 "$KEYCLOAK/realms/$REALM/.well-known/openid-configuration" 2>/dev/null || true)
case $disc in
  *"/realms/$REALM\""*) pass "discovery names realm $REALM" ;;
  *) fail "discovery for realm $REALM did not answer" ;;
esac

# Keycloak shows its sign-in page (200) for a client and redirect it knows, and refuses (400) others.
for spec in $CLIENTS; do
  id=${spec%%|*}; rest=${spec#*|}; host=${rest%%|*}; path=${rest#*|}
  ru="https://$host.$SUFFIX.$ZONE$path"
  c=$(code -G "$auth" --data-urlencode "client_id=$id" --data-urlencode "redirect_uri=$ru" \
        --data-urlencode "response_type=code" --data-urlencode "scope=openid")
  [ "$c" = 200 ] && pass "keycloak sign-in page for client $id and its redirect (HTTP 200)" \
                 || { h=$(curl -sS -o /dev/null -m 20 -D - -G "$auth" --data-urlencode "client_id=$id" --data-urlencode "redirect_uri=$ru" \
                          --data-urlencode "response_type=code" --data-urlencode "scope=openid" 2>/dev/null | tr -d '\r')
                      fail "keycloak answered HTTP $c for client $id and its redirect, not the sign-in page (goes to path: $(where "$(sloc "$h")"))"; }
done
c=$(code -G "$auth" --data-urlencode "client_id=login-probe-no-such-client" \
      --data-urlencode "redirect_uri=https://x.example.com/" --data-urlencode "response_type=code" --data-urlencode "scope=openid")
[ "$c" != 200 ] && pass "keycloak refuses an unknown client (HTTP $c), so the 200s above mean something" \
                || fail "keycloak showed a sign-in page for a client that does not exist"

echo "argo cd"
s=$(curl -sS -m 20 "$ARGOCD/api/v1/settings" 2>/dev/null || true)
case $s in
  *'"name":"Lab sign-in"'*) pass "argo cd settings list the provider Lab sign-in" ;;
  *) fail "argo cd settings do not list the provider Lab sign-in" ;;
esac
h=$(hdrs "$ARGOCD/auth/login?return_url=%2F"); loc=$(sloc "$h")
case $loc in
  *"/realms/$REALM/protocol/openid-connect/auth"*"client_id=argocd"*) pass "argo cd sends its login to keycloak realm $REALM" ;;
  *) fail "argo cd login did not redirect to keycloak (HTTP $(scode "$h"), goes to path: $(where "$loc"))" ;;
esac

echo "jellyfin"
h=$(hdrs "$JELLYFIN/sso/OID/start/keycloak"); loc=$(sloc "$h")
case $loc in
  *"/realms/$REALM/protocol/openid-connect/auth"*"client_id=jellyfin"*) pass "jellyfin's SSO plugin starts a login at keycloak" ;;
  *) fail "jellyfin's SSO plugin did not start a login at keycloak (HTTP $(scode "$h"), goes to path: $(where "$loc"))" ;;
esac

# The last line is the verdict. A failed check fails the Job, so the CronJob's Job list shows it.
if [ "$fails" = 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($fails checks)"; fi
[ "$fails" = 0 ]
