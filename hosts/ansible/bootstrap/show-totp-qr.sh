#!/usr/bin/env bash
# Show one lab user's TOTP seed (D-0037 rule 6) as a QR code on the controller's own screen, so the owner
# adds it to an authenticator app by scanning, with no value typed, pasted, printed or logged.
# Run on the controller (the owner's Mac), from hosts/ansible, after playbooks/k8s-identity.yml made the seed:
#   bootstrap/show-totp-qr.sh <user name> [<seconds the image stays, default 120>]
# Needs qrencode (LGPL-2.1; brew install qrencode). The seed goes to qrencode on stdin, never in an argument;
# the image is a 0600 file in a 0700 temporary folder, opened once, and deleted after the given seconds, or
# sooner when Enter is pressed at a terminal. It prints only status lines.
set -euo pipefail
user=${1:?usage: $0 <user name> [<seconds>]}
seconds=${2:-120}
[[ $user =~ ^[A-Za-z0-9._@-]+$ && $seconds =~ ^[0-9]+$ ]] || { echo "show-totp-qr: bad user name or seconds" >&2; exit 2; }
values=${K8S_IDENTITY_VALUES_FILE:-$HOME/.config/central-hub/identity.env}
key=TOTP_$(printf '%s' "$user" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')
command -v qrencode >/dev/null || { echo "show-totp-qr: qrencode is missing (brew install qrencode)" >&2; exit 1; }
[[ -r $values ]] || { echo "show-totp-qr: $values is missing; run playbooks/k8s-identity.yml first" >&2; exit 1; }
seed=$(sed -n "s/^${key}=//p" "$values" | head -1)
[[ $seed =~ ^[A-Z2-7]{16,}=*$ ]] || { echo "show-totp-qr: $values has no base32 $key line; is $user in lab-admins?" >&2; exit 1; }

umask 077
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
img=$dir/totp.png
# otpauth URI (Google Authenticator's key URI format); the label and issuer are "Lab", never a host name.
printf 'otpauth://totp/Lab:%s?secret=%s&issuer=Lab&algorithm=SHA1&digits=6&period=30' "$user" "${seed%%=*}" |
  qrencode -t PNG -s 8 -o "$img"
chmod 0600 "$img"
opener=$(command -v open || command -v xdg-open) || { echo "show-totp-qr: no open or xdg-open to show the image" >&2; exit 1; }
"$opener" "$img"
echo "show-totp-qr: showing $user's code for ${seconds}s; scan it, then close the image window (Preview keeps showing it after the file is gone)"
if [[ -t 0 ]]; then read -r -t "$seconds" _ || true; else sleep "$seconds"; fi
echo "show-totp-qr: image deleted"
