#!/usr/bin/env bash
# Make an iPhone/iPad configuration profile (.mobileconfig) that holds the lab ROOT certificate and nothing else.
# Usage: hosts/ios-trust-profile.sh <root.crt> [expected sha256 fingerprint] > lab-root.mobileconfig
# The root certificate is public. The profile carries no key, no password and no host name. The two identifiers are made from the
# certificate's own fingerprint, so the same root always gives the same profile and a later install replaces the earlier one.
# Reading and checking only: it writes to standard output.
set -euo pipefail
crt=${1:?usage: ios-trust-profile.sh <root.crt> [sha256 fingerprint]}
want=${2:-}
fp=$(openssl x509 -in "$crt" -noout -fingerprint -sha256 | cut -d= -f2)
w=${want//:/}; f=${fp//:/}
if [[ -n $want && ${w^^} != "${f^^}" ]]; then echo "ios-trust-profile: fingerprint $fp is not the one named; stopped" >&2; exit 1; fi
openssl x509 -in "$crt" -noout -text | grep -q 'CA:TRUE' || { echo "ios-trust-profile: that certificate is not a CA; stopped" >&2; exit 1; }
openssl x509 -in "$crt" -noout -subject | grep -q 'CN *= *Home Lab Root CA' || { echo "ios-trust-profile: that is not the lab root; stopped" >&2; exit 1; }
b64=$(openssl x509 -in "$crt" -outform DER | base64 | tr -d '\n')
python3 -I - "$fp" "$b64" <<'PY'
import sys, uuid, plistlib, base64
fp, b64 = sys.argv[1:3]
ns = uuid.UUID("6f5f5c0e-2b1e-5b7a-9a43-0c1f6d1a7a11")
cert_id = str(uuid.uuid5(ns, "cert " + fp)).upper()
prof_id = str(uuid.uuid5(ns, "profile " + fp)).upper()
profile = {
    "PayloadType": "Configuration",
    "PayloadVersion": 1,
    "PayloadIdentifier": "lab.root-ca.profile",
    "PayloadUUID": prof_id,
    "PayloadDisplayName": "Home Lab Root CA",
    "PayloadDescription": "Trusts certificates issued by the home lab's own CA. Holds only the public root certificate.",
    "PayloadOrganization": "Home Lab",
    "PayloadRemovalDisallowed": False,
    "PayloadContent": [{
        "PayloadType": "com.apple.security.root",
        "PayloadVersion": 1,
        "PayloadIdentifier": "lab.root-ca.certificate",
        "PayloadUUID": cert_id,
        "PayloadDisplayName": "Home Lab Root CA",
        "PayloadCertificateFileName": "lab-root.cer",
        "PayloadContent": base64.b64decode(b64),
    }],
}
sys.stdout.buffer.write(plistlib.dumps(profile, fmt=plistlib.FMT_XML))
PY
