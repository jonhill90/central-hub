#!/bin/bash
# Managed by Ansible (role proxmox_proxy). The proof that the proxy on 443 and 80 works, from the host itself:
# the front page and an unauthenticated API call over 443 with the lab chain verified, a WebSocket upgrade
# that reaches pveproxy (its 401, not the proxy's 400 or 502), and the redirect on 80. --resolve pins the
# name to 127.0.0.1, so it needs no DNS. Prints one line per proof; exits non-zero when any fails.
set -uo pipefail
# shellcheck source=/dev/null
. /etc/proxmox-proxy/proofs.env
base=(curl -sS --max-time 20 -o /dev/null --cacert "$PROOF_CA" --resolve "$PROOF_NAME:443:127.0.0.1")
in_list() { local x; for x in $2; do [ "$1" = "$x" ] && return 0; done; return 1; }
fail=0
front=$("${base[@]}" -w '%{http_code}' "https://$PROOF_NAME/")
in_list "$front" "$PROOF_FRONT_OK" && echo "ok front $front" || { echo "FAIL front $front"; fail=1; }
api=$("${base[@]}" -w '%{http_code}' "https://$PROOF_NAME/api2/json/version")
in_list "$api" "$PROOF_API_OK" && echo "ok api $api" || { echo "FAIL api $api"; fail=1; }
ws=$("${base[@]}" --http1.1 -w '%{http_code}' \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  "https://$PROOF_NAME/api2/json/nodes/$PROOF_NODE/vncwebsocket?port=5900&vncticket=none")
in_list "$ws" "$PROOF_API_OK" && echo "ok websocket $ws" || { echo "FAIL websocket $ws"; fail=1; }
redirect=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code} %{redirect_url}' \
  --resolve "$PROOF_NAME:80:127.0.0.1" "http://$PROOF_NAME/")
case $redirect in
  "301 https://$PROOF_NAME/"*) echo "ok redirect $redirect" ;;
  *) echo "FAIL redirect $redirect"; fail=1 ;;
esac
exit "$fail"
