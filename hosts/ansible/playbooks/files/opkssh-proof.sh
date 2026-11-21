#!/bin/bash
# Dev only, for the opkssh proof (playbooks/k8s-ssh-ca-proof.yml). Run as root on dev's first control-plane node:
#   opkssh-proof.sh <work folder> <Keycloak host> <issuer> <Gateway address> <user>
# The work folder holds dev-ca.pem (the root of dev's own CA), user.json ({"password", "seed"} of <user>) and
# opkssh-proof-login.py.
#
# opkssh (OpenPubkey SSH, Apache-2.0), pinned at v0.19.2 with each file's sha256: it puts the user's Keycloak ID
# token inside an SSH key, and sshd checks it with AuthorizedKeysCommand, so no CA runs. The proof:
#   a temporary public client opkssh-proof in realm lab, with opkssh's localhost callback (made with kcadm inside
#   Keycloak's pod, deleted at the end)
#   this node trusts dev's CA and sends Keycloak's name to dev's Gateway while the proof runs (dev's names
#   otherwise resolve to prod's Gateway)
#   opkssh installed with its own script (its SELinux module included), realm lab as its only provider, and
#   <user> allowed as local account opkproof only
#   `opkssh login` with the browser played by opkssh-proof-login.py; ssh as opkproof logs in; ssh as another local
#   account is refused
# Prints "opkssh: ..." lines only and ends "opkssh: PASS: ..." or "opkssh: FAIL: ...". Exit 0 on PASS. The node is
# torn down with dev at the end of the run, so opkssh itself stays installed until then; the rest is undone here.
set -uo pipefail
umask 077
work=$1 kc_host=$2 issuer=$3 gw=$4 user=$5
acct=opkproof other=opkother client=opkssh-proof
ver=v0.19.2
base=https://github.com/openpubkey/opkssh/releases/download/$ver raw=https://raw.githubusercontent.com/openpubkey/opkssh/refs/tags/$ver
declare -A pin=(
  [opkssh-linux-amd64]=e799b780d5477e8d986a2e6784773ebb2451d860dd842d23e271baf88aee2da3
  [install-linux.sh]=a83a51651d69e2e567c46952cb4931e3c9745d4b4984f074b990924d052a1509
  [opkssh.te]=b37a9a53b1d46d30e5861b1f897d6c9ef796ed4385056f8d93608977c9460b1c
)
kc() { kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"; }
say() { echo "opkssh: $*"; }
fails=0
check() { local name=$1; shift; if "$@"; then say "$name: ok"; else say "$name: FAIL"; fails=$((fails + 1)); fi; }
hosts_mark="# ssh-ca-proof"
kcadm() { # kcadm <args...>: Keycloak's admin CLI inside its pod, signed in as the operator's first admin
  kc -n identity exec -i sso-0 -- sh -c '
    /opt/keycloak/bin/kcadm.sh config credentials --config /tmp/kcadm.config --server http://localhost:8080 --realm master \
      --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1 &&
    /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config; rc=$?; rm -f /tmp/kcadm.config; exit $rc' _ "$@"
}
client_id=""
cleanup() {
  [ -z "$client_id" ] || kcadm delete "clients/$client_id" -r lab >/dev/null 2>&1 || say "note: the temporary client was not deleted (dev is torn down at the end of the run)"
  sed -i "/$hosts_mark\$/d" /etc/hosts
  rm -f /etc/pki/ca-trust/source/anchors/ssh-ca-proof-dev-ca.pem && update-ca-trust >/dev/null 2>&1 || true
  userdel -r "$acct" >/dev/null 2>&1 || true
  userdel -r "$other" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for f in dev-ca.pem user.json opkssh-proof-login.py; do
  [ -s "$work/$f" ] || { say "FAIL: $f is missing from the work folder"; exit 1; }
done

# 1. The pinned files, each checked against its sha256 before use.
for f in "${!pin[@]}"; do
  url=$base/$f; [ "$f" = opkssh-linux-amd64 ] || url=$raw/${f/install-linux.sh/scripts/install-linux.sh}
  curl -fsSL --max-time 120 -o "$work/$f" "$url" || { say "FAIL: could not download $f"; exit 1; }
  echo "${pin[$f]}  $work/$f" | sha256sum -c --status || { say "FAIL: $f does not match its pinned sha256"; exit 1; }
done
say "files: opkssh $ver binary, install script and SELinux policy match their pinned sha256"

# 2. Keycloak's name to dev's Gateway, and dev's CA trusted, for opkssh on both sides.
echo "$gw $kc_host $hosts_mark" >> /etc/hosts
cp "$work/dev-ca.pem" /etc/pki/ca-trust/source/anchors/ssh-ca-proof-dev-ca.pem && update-ca-trust
curl -fsS --max-time 20 -o /dev/null "$issuer/.well-known/openid-configuration" || { say "FAIL: this node can't read realm lab's discovery over HTTPS"; exit 1; }
say "keycloak: realm lab's discovery answers over HTTPS with dev's CA trusted"

# 3. The temporary public client, with opkssh's three localhost callbacks (opkssh README, "Redirect URIs").
out=$(kcadm create clients -r lab -s clientId=$client -s publicClient=true -s standardFlowEnabled=true \
  -s directAccessGrantsEnabled=false -s 'redirectUris=["http://localhost:3000/login-callback","http://localhost:10001/login-callback","http://localhost:11110/login-callback"]' -i 2>&1)
client_id=$(printf '%s\n' "$out" | grep -E '^[0-9a-f-]{36}$' | head -n 1)
[ -n "$client_id" ] || { say "FAIL: could not make client $client: $(printf '%s' "$out" | tr -s '\n' ' ' | cut -c1-200)"; exit 1; }
say "keycloak: temporary public client $client made in realm lab"

# 4. The server side: opkssh's own installer, realm lab as the only provider, one identity for one account.
if ! bash "$work/install-linux.sh" --install-from="$work/opkssh-linux-amd64" --install-te-from="$work/opkssh.te" --no-home-policy > "$work/install.log" 2>&1; then
  say "FAIL: opkssh's installer failed: $(tail -n 3 "$work/install.log" | tr -s '\n' ' ' | cut -c1-200)"; exit 1
fi
useradd -m -s /bin/bash "$acct" >/dev/null 2>&1 || true
useradd -m -s /bin/bash "$other" >/dev/null 2>&1 || true
email=$(kcadm get users -r lab -q "username=$user" --fields email --format csv --noquotes 2>/dev/null | head -n 1)
[ -n "$email" ] || { say "FAIL: could not read $user's email in realm lab"; exit 1; }
echo "$issuer $client 24h" > /etc/opk/providers
echo "$acct $email $issuer" > /etc/opk/auth_id
chown root:opksshuser /etc/opk/providers /etc/opk/auth_id && chmod 640 /etc/opk/providers /etc/opk/auth_id
systemctl reload sshd; sleep 2
say "server: opkssh $ver installed; provider realm lab, client $client; $user may log in as $acct only (getenforce: $(getenforce 2>/dev/null || echo none))"

# 5. The client side: opkssh login, with the browser played by the script.
mkdir -p "$work/home"
HOME=$work/home timeout 120 /usr/local/bin/opkssh login --provider="$issuer,$client" --disable-browser-open -i "$work/opk" > "$work/login.out" 2>&1 &
lp=$!
url=""
for _ in $(seq 1 30); do
  url=$(grep -oE 'https?://[^ "<>]+' "$work/login.out" | head -n 1); [ -n "$url" ] && break; sleep 1
done
[ -n "$url" ] || { say "FAIL: opkssh login printed no address to open"; kill $lp 2>/dev/null; exit 1; }
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); c.update(url=sys.argv[2], user=sys.argv[3]); print(json.dumps(c))' "$work/user.json" "$url" "$user" |
  python3 -I "$work/opkssh-proof-login.py"
wait $lp; lrc=$?
check "login: opkssh login ended with an SSH key holding $user's Keycloak token" test "$lrc" -eq 0 -a -s "$work/opk"
try() { # account, expected output or ""
  local out
  out=$(ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 -i "$work/opk" "$1@127.0.0.1" id -un 2>/dev/null) || true
  [ "$out" = "$2" ]
}
check "ssh: the opkssh key logs in as $acct" try "$acct" "$acct"
check "ssh: the same key is refused as $other, which auth_id does not name" try "$other" ""
say "note: opkssh keys end at the provider line's 24h, the shortest it offers is 12h, and it has no revocation list (README, /etc/opk/providers)"

if [ "$fails" -eq 0 ]; then say "PASS: Keycloak sign-in through opkssh, ssh login, and a refused account"; exit 0; fi
say "FAIL: $fails check(s) failed"; exit 1
