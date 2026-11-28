#!/bin/sh
set -eu
# Fetch one commit by its full sha with git, check it, build the API (TypeScript), and keep only what it runs from.
cd /work
rm -rf src /out/* /out/.[!.]* 2>/dev/null || true
mkdir src
cd src
git init -q
git remote add origin "$REPO_URL"
git fetch -q --depth 1 origin "$COMMIT"
git checkout -q FETCH_HEAD
test "$(git rev-parse HEAD)" = "$COMMIT"
cd services/api
npm ci --no-audit --no-fund
npm run build
npm prune --omit=dev --no-audit --no-fund
cp -r dist node_modules package.json /out/
echo "built api $COMMIT"
