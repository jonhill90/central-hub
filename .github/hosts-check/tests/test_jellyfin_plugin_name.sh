#!/usr/bin/env bash
# The Jellyfin setup script's plugin check (hosts/kubernetes/home/c1/apps/jellyfin/files/setup.sh, "sso 2/4"): it takes the
# grep out of the script itself and runs it on sample GET /Plugins replies.
#   1. The names c1's Jellyfin 12 listed on 2026-11-18, which hold "SSO-Auth", match.
#   2. meta.json's name, "SSO Authentication", still matches, in either key case, with or without spaces.
#   3. A reply with other plugins only, an empty reply and a similar name ("SSO-Authx") do not match.
# Usage: .github/hosts-check/tests/test_jellyfin_plugin_name.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
script=hosts/kubernetes/home/c1/apps/jellyfin/files/setup.sh
pat=$(sed -n "s/^until api -H \"\$authz\" \"\$BASE\/Plugins\" | grep -Eiq '\(.*\)'; do\$/\1/p" "$script")
[ -n "$pat" ] || { echo "FAIL could not read the plugin check from $script"; exit 1; }
listed() { printf '%s' "$1" | grep -Eiq "$pat"; }
live='[{"Name":"AudioDB"},{"Name":"ListenBrainz Similarity Provider"},{"Name":"MusicBrainz"},{"Name":"OMDb"},{"Name":"SSO-Auth"},{"Name":"Studio Images"},{"Name":"TMDb"}]'
listed "$live" && ok "1 the names c1 listed match" || bad "1 live names did not match"
listed '[{"Name":"SSO Authentication"}]' && listed '[{"name": "SSO Authentication"}]' && listed '[ { "name" : "sso-auth" } ]' &&
  ok "2 meta.json's name, either key case and spacing, matches" || bad "2 the other spellings did not match"
if ! listed '[{"Name":"AudioDB"},{"Name":"TMDb"}]' && ! listed '' && ! listed '[{"Name":"SSO-Authx"}]'; then
  ok "3 other plugins, an empty reply and a similar name do not match"
else bad "3 a wrong reply matched"; fi
exit "$fail"
