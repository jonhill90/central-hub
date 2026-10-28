#!/usr/bin/env bash
# Test cases for check_gate.py: each breaks a copy of the repo one way and expects the check to
# fail; the unbroken copy must pass. Run from anywhere; the gate workflow runs it.
set -euo pipefail
cd "$(dirname "$0")/../../.."
check=$PWD/.github/gate-check/check_gate.py
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0

fresh() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo"
  git ls-files -z | xargs -0 cp --parents -t "$work/repo"
  git -C "$work/repo" init -q
  git -C "$work/repo" add -A
}

expect() { # expect pass|fail <name>
  local want=$1 name=$2 got=pass
  git -C "$work/repo" add -A
  python3 "$check" "$work/repo" >"$work/out" 2>&1 || got=fail
  if [ "$got" = "$want" ]; then
    echo "ok: $name"
  else
    echo "NOT OK: $name: expected $want, got $got"
    cat "$work/out"
    failed=1
  fi
}

wf=.github/workflows/docs.yml

fresh
expect pass "the repo as it is"

fresh
sed -i 's/^  pull_request: .*/  pull_request_target:/' "$work/repo/$wf"
expect fail "a pull_request_target trigger"

fresh
sed -i 's/^  contents: read/  contents: write/' "$work/repo/$wf"
expect fail "a write permission at the top"

fresh
sed -i '0,/^    runs-on:/s//    permissions:\n      pull-requests: write\n    runs-on:/' "$work/repo/$wf"
expect fail "a write permission in a job"

fresh
sed -i '0,/          persist-credentials: false/s//          persist-credentials: true/' "$work/repo/$wf"
expect fail "a checkout that keeps its token"

fresh
sed -i '0,/actions\/checkout@[0-9a-f]\{40\}/s//actions\/checkout@v7/' "$work/repo/$wf"
expect fail "an action pinned to a tag"

fresh
sed -i '0,/        env:/s//        env:\n          TOKEN: ${{ secrets.SOME_TOKEN }}/' "$work/repo/$wf"
expect fail "a secret read"

fresh
printf 'apiVersion: image.toolkit.fluxcd.io/v1\nkind: ImageUpdateAutomation\n' > "$work/repo/hosts/ansible/roles/k8s_gitops/templates/x.yaml.j2"
expect fail "a Flux image automation object (item 6)"

fresh
printf 'url: https://example.invalid/argocd-image-updater/install.yaml\n' > "$work/repo/hosts/ansible/roles/k8s_gitops/templates/y.yml"
expect fail "the Argo CD Image Updater (item 6)"

fresh
sed -i "0,/        env:/s//        env:\n          TOKEN: \${{ secrets['SOME_TOKEN'] }}/" "$work/repo/$wf"
expect fail "a secret read by index"

fresh
sed -i '0,/        env:/s//        env:\n          ALL: ${{ toJSON(secrets) }}/' "$work/repo/$wf"
expect fail "every secret read at once"

fresh
printf 'apiVersion: image.toolkit.fluxcd.io/v1\nkind: "ImagePolicy"\n' > "$work/repo/hosts/ansible/roles/k8s_gitops/templates/z.yaml.j2"
expect fail "a quoted image automation kind (item 6)"

exit $failed
