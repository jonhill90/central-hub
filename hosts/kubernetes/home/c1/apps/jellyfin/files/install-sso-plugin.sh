#!/bin/sh
# Init container for Jellyfin: installs the SSO plugin and builds the CA bundle.
# Runs as the same user as Jellyfin (uid 1000) so the plugin files belong to it. No heredocs: the
# root filesystem is read-only. Safe to run again: it changes nothing once the plugin is there.
set -eu
dir="/config/plugins/SSO-Auth_$PLUGIN_VERSION"

# 1/2 the CA bundle: the image's public roots plus the lab root, for SSL_CERT_FILE (.NET reads only
# that file when it is set, so the public roots must be in it too). The lab root is not in git: the
# Secret media/jellyfin-lab-root-ca comes from an Ansible run (role k8s_identity, from the
# controller's file). With no Secret yet, Jellyfin starts as before and the setup Job skips the
# sign-in; a file with no certificate in it is an error, never trusted.
cp /etc/ssl/certs/ca-certificates.crt /tls/ca-bundle.crt
if [ -e /lab-ca/lab-root-ca.pem ]; then
  grep -q 'BEGIN CERTIFICATE' /lab-ca/lab-root-ca.pem || { echo "lab-root-ca.pem holds no certificate" >&2; exit 1; }
  cat /lab-ca/lab-root-ca.pem >> /tls/ca-bundle.crt
else
  echo "no lab root yet (Secret jellyfin-lab-root-ca): sign-in stays off until it exists"
fi
echo "ca bundle: $(grep -c 'BEGIN CERTIFICATE' /tls/ca-bundle.crt) certificates"

# 2/2 the plugin.
if [ -f "$dir/SSO-Auth.dll" ] && [ -f "$dir/meta.json" ]; then
  echo "plugin $PLUGIN_VERSION already in $dir"
  exit 0
fi
curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 -o /tmp/sso.zip "$PLUGIN_URL"
echo "$PLUGIN_SHA256  /tmp/sso.zip" | sha256sum -c -
mkdir -p /config/plugins
rm -rf /config/plugins/SSO-Auth_*
mkdir -p "$dir"
unzip -q -o /tmp/sso.zip -d "$dir"
test -f "$dir/SSO-Auth.dll"
echo "plugin $PLUGIN_VERSION installed in $dir"
