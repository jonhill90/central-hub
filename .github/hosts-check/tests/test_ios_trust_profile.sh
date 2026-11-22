#!/usr/bin/env bash
# hosts/ios-trust-profile.sh makes a profile that holds the lab root certificate and nothing else, and refuses the wrong certificate.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(cd "$here/../.." && pwd)
script=$root/hosts/ios-trust-profile.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "not ok  $1"; fail=1; }
mk() { # <name> <CN> <ca true|false>
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$t/$1.key" -out "$t/$1.crt" -days 5 -subj "/CN=$2" \
    -addext "basicConstraints=critical,CA:$3" >/dev/null 2>&1
}
mk root "Home Lab Root CA" true; mk other "Some Other CA" true; mk leaf "Home Lab Root CA" false
fp=$(openssl x509 -in "$t/root.crt" -noout -fingerprint -sha256 | cut -d= -f2)
"$script" "$t/root.crt" "$fp" > "$t/a.mobileconfig"; "$script" "$t/root.crt" "${fp//:/}" > "$t/b.mobileconfig"
cmp -s "$t/a.mobileconfig" "$t/b.mobileconfig" && ok "the same root gives the same profile, with or without colons in the fingerprint" || bad "profile differs"
res=$(python3 -I - "$t/a.mobileconfig" "$t/root.crt" <<'PY'
import plistlib, sys, subprocess
d = plistlib.load(open(sys.argv[1], "rb")); p = d["PayloadContent"]
der = subprocess.run(["openssl", "x509", "-in", sys.argv[2], "-outform", "DER"], capture_output=True, check=True).stdout
print(len(p), p[0]["PayloadType"], p[0]["PayloadContent"] == der, sorted(d) == sorted(set(d)))
PY
)
[ "$res" = "1 com.apple.security.root True True" ] && ok "one root payload that is exactly the certificate" || bad "payload: $res"
grep -qi "PRIVATE KEY" "$t/a.mobileconfig" && bad "a key is in the profile" || ok "no key in the profile"
"$script" "$t/root.crt" 00:11 >/dev/null 2>&1 && bad "a wrong fingerprint was accepted" || ok "a wrong fingerprint stops it"
"$script" "$t/other.crt" >/dev/null 2>&1 && bad "another CA was accepted" || ok "a CA with another name stops it"
"$script" "$t/leaf.crt" >/dev/null 2>&1 && bad "a non-CA was accepted" || ok "a certificate that is not a CA stops it"
exit $fail
