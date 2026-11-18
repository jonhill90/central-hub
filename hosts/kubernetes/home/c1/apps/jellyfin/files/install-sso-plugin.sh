#!/bin/sh
# Init container for Jellyfin: installs the SSO plugin and builds the CA bundle.
# Runs as the same user as Jellyfin (uid 1000) so the plugin files belong to it. No heredocs: the
# root filesystem is read-only. Safe to run again: it changes nothing once the plugin is there.
set -eu
dir="/config/plugins/SSO-Auth_$PLUGIN_VERSION"

# 1/2 the CA bundle: the image's public roots plus the lab root, for SSL_CERT_FILE (.NET reads only
# that file when it is set, so the public roots must be in it too).
cat /etc/ssl/certs/ca-certificates.crt /lab-ca/lab-root-ca.pem > /tls/ca-bundle.crt
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
