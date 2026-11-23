#!/bin/sh
set -eu
# Runs as root before Home Assistant starts. Installs hass-oidc-auth into /config/custom_components from the pinned
# archive (sha256 checked) and writes configuration.yaml from the chart. Safe to run again.
cfg=/config
mkdir -p "$cfg/custom_components"
marker="$cfg/custom_components/auth_oidc/.pinned"
if [ "$(cat "$marker" 2>/dev/null || true)" != "$PLUGIN_SHA256" ]; then
  curl -fsSL --retry 5 --retry-delay 3 -o /tmp/oidc.tgz "$PLUGIN_URL"
  echo "$PLUGIN_SHA256  /tmp/oidc.tgz" | sha256sum -c -
  mkdir -p /tmp/oidc
  tar -xzf /tmp/oidc.tgz -C /tmp/oidc
  rm -rf "$cfg/custom_components/auth_oidc"
  cp -r "/tmp/oidc/hass-oidc-auth-$PLUGIN_VERSION/custom_components/auth_oidc" "$cfg/custom_components/auth_oidc"
  echo "$PLUGIN_SHA256" > "$marker"
  echo "installed hass-oidc-auth $PLUGIN_VERSION"
else
  echo "hass-oidc-auth $PLUGIN_VERSION already installed"
fi
# The chart owns configuration.yaml; the UI's own files stay on the volume.
cp /chart/configuration.yaml "$cfg/configuration.yaml"
for f in automations.yaml scenes.yaml; do
  [ -e "$cfg/$f" ] || echo '[]' > "$cfg/$f"
done
[ -e "$cfg/scripts.yaml" ] || echo '{}' > "$cfg/scripts.yaml"
