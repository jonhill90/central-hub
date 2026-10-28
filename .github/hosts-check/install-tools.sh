#!/usr/bin/env bash
# Build the Go tools the hosts checks need, from source at pinned versions (STD-0005).
# Usage: .github/hosts-check/install-tools.sh [bin-dir [tool...]]   (default: .github/hosts-check/.tools/bin,
# all of tofu, tflint and kubeconform)
# Needs: Go. go fetches each module through the Go module proxy and checks it against the Go
# checksum database (sum.golang.org), so a pinned version always builds from the same source.
# Versions: the newest release at least two weeks old on 2026-10-27 (STD-0003 rule 1).
set -euo pipefail
cd "$(dirname "$0")/../.."
bin=$(realpath -m "${1:-.github/hosts-check/.tools/bin}")
shift || true
want=" ${*:-tofu tflint kubeconform} "
mkdir -p "$bin"
export GOTOOLCHAIN=auto GOFLAGS=-mod=mod

TOFU_VERSION=v1.13.1         # 2026-10-01; v1.13.2 and v1.12.9 (2026-10-21) are under two weeks old
TFLINT_VERSION=v0.64.0       # 2026-07-17; v0.65.0 (2026-10-22) is under two weeks old
KUBECONFORM_VERSION=v0.8.0   # 2026-06-04

# OpenTofu's go.mod has replace directives, so `go install pkg@version` refuses it: download the
# module (checked against the checksum database), then build it in a writable copy.
build_module() {
  local module=$1 pkg=$2 out=$3 ldflags=${4:-} dir work
  dir=$(go mod download -json "$module" | python3 -c 'import json, sys; print(json.load(sys.stdin)["Dir"])')
  work=$(mktemp -d)
  cp -r "$dir/." "$work"
  chmod -R u+w "$work"
  (cd "$work" && go build -trimpath -ldflags "$ldflags" -o "$bin/$out" "$pkg")
  rm -rf "$work"
}

if [[ $want == *" tofu "* ]]; then
  # dev=no drops the "-dev" mark, as OpenTofu's own release builds do.
  build_module "github.com/opentofu/opentofu@$TOFU_VERSION" ./cmd/tofu tofu "-X github.com/opentofu/opentofu/version.dev=no"
  "$bin/tofu" version
fi
if [[ $want == *" tflint "* ]]; then
  GOBIN=$bin go install "github.com/terraform-linters/tflint@$TFLINT_VERSION"
  "$bin/tflint" --version
fi
if [[ $want == *" kubeconform "* ]]; then
  GOBIN=$bin go install "github.com/yannh/kubeconform/cmd/kubeconform@$KUBECONFORM_VERSION"
  "$bin/kubeconform" -v
fi
