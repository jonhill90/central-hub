#!/bin/sh
set -eu
# Read the realm's public address and the client secret from the mounted Secrets, make a session key for this pod, start the UI.
# A rebuild starts this pod before the identity stage makes the Secrets, so until they exist a small stand-in answers on the
# port (200 on /api/health so the apps stage can finish, 503 elsewhere), then this script starts the real UI.
D=/var/run/hill90/oidc
if [ ! -s "$D/issuer" ] || [ ! -s "$D"/client-secret ]; then
  node -e '
    const fs=require("fs"),http=require("http");
    const ready=()=>fs.existsSync("/var/run/hill90/oidc/issuer")&&fs.existsSync("/var/run/hill90/oidc/client-secret");
    http.createServer((q,r)=>{r.statusCode=q.url==="/api/health"?200:503;r.end("hill90-app: sign-in not configured yet\n")}).listen(3000,"0.0.0.0");
    setInterval(()=>{if(ready())process.exit(0)},5000);
  '
fi
AUTH_KEYCLOAK_ISSUER="$(cat "$D"/issuer)"
export AUTH_KEYCLOAK_ISSUER
AUTH_KEYCLOAK_SECRET="$(cat "$D"/client-secret)"
export AUTH_KEYCLOAK_SECRET
AUTH_URL="$(cut -d, -f1 "$D"/public-urls)"
export AUTH_URL
AUTH_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export AUTH_SECRET
API_WS_URL="wss://$(cut -d, -f1 "$D"/public-urls | sed 's#^https://##')"
export API_WS_URL
exec node server.js
