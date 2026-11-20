#!/bin/sh
set -eu
# Fetch one commit by its full sha with git (not a tarball), check it, then build the standalone output.
cd /work
rm -rf src /out/* /out/.[!.]* 2>/dev/null || true
mkdir src
cd src
git init -q
git remote add origin "$REPO_URL"
git fetch -q --depth 1 origin "$COMMIT"
git checkout -q FETCH_HEAD
test "$(git rev-parse HEAD)" = "$COMMIT"
npm ci --no-audit --no-fund
npm run build
cp -r .next/standalone/. /out/
mkdir -p /out/.next
cp -r .next/static /out/.next/static
cp -r catalog /out/catalog
echo "built $COMMIT"
