#!/bin/sh
set -eu
# Make the app's own secrets once (they live on the state volume, so a restart keeps them), then start the API.
S=/state
umask 077
[ -s $S/provider-key ] || openssl rand -hex 32 > $S/provider-key
[ -s $S/chat-callback ] || openssl rand -hex 32 > $S/chat-callback
[ -s $S/akm-token ] || openssl rand -hex 32 > $S/akm-token
[ -s $S/mr-token ] || openssl rand -hex 32 > $S/mr-token
[ -s $S/akm.pem ] || openssl genpkey -algorithm ed25519 -out $S/akm.pem 2>/dev/null
[ -s $S/mr.pem ] || openssl genpkey -algorithm ed25519 -out $S/mr.pem 2>/dev/null
export PROVIDER_KEY_ENCRYPTION_KEY="$(cat $S/provider-key)"
export CHAT_CALLBACK_TOKEN="$(cat $S/chat-callback)"
export AKM_INTERNAL_SERVICE_TOKEN="$(cat $S/akm-token)"
export MODEL_ROUTER_INTERNAL_SERVICE_TOKEN="$(cat $S/mr-token)"
export AKM_SIGNING_PRIVATE_KEY="$(awk 'BEGIN{ORS="\\n"}{print}' $S/akm.pem)"
export MODEL_ROUTER_SIGNING_PRIVATE_KEY="$(awk 'BEGIN{ORS="\\n"}{print}' $S/mr.pem)"
export KEYCLOAK_ISSUER="$(cat /var/run/hill90/oidc/issuer)"
exec node dist/index.js
