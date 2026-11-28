#!/bin/sh
set -eu
# Fetch one commit by its full sha with git, check it, then build the UI's standalone output.
cd /work
rm -rf src /out/* /out/.[!.]* 2>/dev/null || true
mkdir src
cd src
git init -q
git remote add origin "$REPO_URL"
git fetch -q --depth 1 origin "$COMMIT"
git checkout -q FETCH_HEAD
test "$(git rev-parse HEAD)" = "$COMMIT"
cd services/ui
# The app's own image build leaves its tests out (.dockerignore: src/__tests__); its type check fails on them.
rm -rf src/__tests__
npm ci --no-audit --no-fund
npm run build
cp -r .next/standalone/. /out/
mkdir -p /out/.next
cp -r .next/static /out/.next/static
cp -r public /out/public
echo "built ui $COMMIT"
