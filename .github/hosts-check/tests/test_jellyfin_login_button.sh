#!/usr/bin/env bash
# The Jellyfin setup script's login button (hosts/kubernetes/home/c1/apps/jellyfin/files/setup.sh, "sso 4/4"): the real
# script runs against a stand-in curl that plays Jellyfin, with the wizard done, the plugin listed and the provider written.
#   1. The run posts one branding body to /System/Configuration/Branding that is valid JSON, whose LoginDisclaimer holds a form
#      posting to the path /sso/OID/start/<provider> (no host name) and the plugin README's button classes, and whose CustomCss
#      holds the README's two rules.
#   2. The anonymous GET /Branding/Configuration then shows the button, and the run ends with its "done" line, rc 0.
#   3. A second run posts the same body (the same state every run).
#   4. When the branding does not show the button after the write (the stand-in drops it), the run fails, rc 1.
# Measured on c1 on 2026-11-19: GET /Branding/Configuration answered {"SplashscreenEnabled":false}, so no button existed.
# Usage: .github/hosts-check/tests/test_jellyfin_login_button.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
script=hosts/kubernetes/home/c1/apps/jellyfin/files/setup.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"; echo "-----BEGIN CERTIFICATE-----" > "$t/ca.pem"
sed "s#/lab-ca/lab-root-ca.pem#$t/ca.pem#" "$script" > "$t/setup.sh"
cat > "$t/bin/curl" <<'S'
#!/bin/bash
# The stand-in Jellyfin: the last argument is the URL; -X names the method; a body arrives on stdin.
url=${*: -1}; method=GET; prev=""
for a in "$@"; do [ "$prev" = -X ] && method=$a; prev=$a; done
body=""; case " $* " in *" @- "*) body=$(cat) ;; esac
w=$STUB_DIR
case "$method $url" in
  "GET "*/health) ;;
  "GET "*/System/Info/Public) echo '{"StartupWizardCompleted":true}' ;;
  "POST "*/Users/AuthenticateByName) echo '{"AccessToken":"stub-token"}' ;;
  "GET "*/Plugins) echo '[{"Name":"SSO-Auth"}]' ;;
  "POST "*/sso/OID/Add/*) ;;
  "GET "*/sso/OID/Get) echo '{"keycloak":{}}' ;;
  "POST "*/System/Configuration/Branding) printf '%s' "$body" >> "$w/posted"; echo >> "$w/posted"
     [ "${DROP:-}" = 1 ] || printf '%s' "$body" > "$w/branding" ;;
  "GET "*/Branding/Configuration) cat "$w/branding" 2>/dev/null || echo '{"SplashscreenEnabled":false}' ;;
  *) echo "stub curl: unexpected $method $url" >> "$w/unexpected" ;;
esac
exit 0
S
chmod +x "$t/bin/curl"
env_run() {
  rm -f "$t/branding" "$t/posted" "$t/unexpected"
  STUB_DIR=$t DROP=${DROP:-} PATH="$t/bin:$PATH" BASE=http://stub ADMIN_USER=u ADMIN_PASSWORD=p METRICS_ENABLED=false \
    SSO_ENABLED=true SSO_PROVIDER=keycloak SSO_ISSUER=https://sso.example.test/realms/lab SSO_CLIENT_ID=jellyfin \
    SSO_CLIENT_SECRET=s SSO_CA_NAME=ca SSO_SECRET_NAME=sec SSO_ROLES="admin viewer" SSO_ADMIN_ROLES=admin \
    sh "$t/setup.sh" > "$t/out" 2>&1
}
env_run; rc=$?
[ "$rc" = 0 ] || { bad "1 the run ended rc $rc: $(tail -3 "$t/out")"; exit 1; }
[ "$(wc -l < "$t/posted")" = 1 ] && ok "1 one branding body was posted" || bad "1 branding posts: $(wc -l < "$t/posted")"
if python3 -I - "$t/posted" <<'PY'
import json, sys
b = json.loads(open(sys.argv[1]).read())
d, c = b["LoginDisclaimer"], b["CustomCss"]
assert 'action="/sso/OID/start/keycloak"' in d, d
assert "raised block emby-button button-submit" in d and "<form" in d and "</form>" in d, d
assert "http" not in d, d
assert "a.raised.emby-button" in c and ".disclaimerContainer" in c and "display: block" in c, c
assert b["SplashscreenEnabled"] is False
PY
then ok "1 the body is JSON; the form posts to the path /sso/OID/start/keycloak, with the README's classes and CSS"; else bad "1 the posted body is wrong: $(cat "$t/posted")"; fi
grep -q "sso/OID/start/keycloak" "$t/branding" && grep -q "^done: sso provider keycloak set" "$t/out" && ok "2 the anonymous branding read shows the button; the run says done" || bad "2 $(tail -3 "$t/out")"
[ ! -e "$t/unexpected" ] && ok "2 the script called nothing the stand-in does not know" || bad "2 unexpected calls: $(cat "$t/unexpected")"
first=$(cat "$t/posted"); env_run
[ "$(cat "$t/posted")" = "$first" ] && ok "3 a second run posts the same body" || bad "3 the second body differs"
DROP=1 env_run; rc=$?
if [ "$rc" = 1 ] && grep -q "the login button is not in the branding after the write" "$t/out"; then
  ok "4 a branding that lacks the button after the write fails the run"; else bad "4 rc $rc: $(tail -2 "$t/out")"; fi
exit "$fail"
