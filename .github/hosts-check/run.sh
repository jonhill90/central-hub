#!/usr/bin/env bash
# Run the hosts checks (STD-0005). CI runs the same commands.
# Usage: .github/hosts-check/run.sh [terraform|ansible|manifests|scripts|all]   (default: all)
# Needs: python3 with requirements.txt installed; tofu, tflint and kubeconform on PATH, or
# TOOLS=<dir> holding them (install-tools.sh builds them); for ansible and manifests, the
# collections in hosts/ansible/requirements.yml (this script installs them when missing).
# TOFU_PLUGIN_DIR=<dir> makes tofu init read providers from that folder instead of the registry,
# for machines that can't download them; the copies then skip the lock file's hash check.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
here=$root/.github/hosts-check
tools=${TOOLS:-$here/.tools/bin}
[ -d "$tools" ] && PATH="$tools:$PATH"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

check_terraform() {
  # STD-0004 rules a script can see, with its own test cases.
  python3 "$here/check_hosts.py" "$root"
  bash "$here/tests/test_check_hosts.sh"
  tofu fmt -check -recursive -diff hosts/terraform
  local folder copy init_args=(-backend=false -input=false -no-color)
  [ -n "${TOFU_PLUGIN_DIR:-}" ] && init_args+=(-plugin-dir="$TOFU_PLUGIN_DIR")
  for folder in hosts/terraform/*/*/; do
    folder=${folder%/}
    ls "$folder"/*.tf >/dev/null 2>&1 || continue
    echo "== $folder"
    # Each folder runs in a copy, so .terraform/ never lands in the repo. tofu test can't import
    # under a mocked provider (OpenTofu 1.13 stops with "Importing is not supported in testing
    # context"), so the copy leaves out imports.tf. The rest of the folder is tested as written.
    copy="$work/$folder"
    mkdir -p "$copy"
    cp -r "$folder/." "$copy"
    rm -f "$copy/imports.tf"
    # Providers built from source locally don't match the lock file's hashes. CI keeps the lock.
    [ -n "${TOFU_PLUGIN_DIR:-}" ] && rm -f "$copy/.terraform.lock.hcl"
    # The shared VLAN file sits at the same path relative to the copy.
    mkdir -p "$work/hosts/ansible/inventories"
    cp -r hosts/ansible/inventories/. "$work/hosts/ansible/inventories"
    (cd "$copy" && tofu init "${init_args[@]}" >/dev/null && tofu validate -no-color)
    (cd "$copy" && tflint --config "$here/tflint.hcl" --format compact)
    if ls "$copy"/tests/*.tftest.hcl >/dev/null 2>&1; then
      (cd "$copy" && tofu test -no-color)
    else
      echo "FAIL: $folder has no tests/*.tftest.hcl (STD-0005 rule 3)" >&2
      return 1
    fi
  done
}

collections() {
  [ -d hosts/ansible/collections/ansible_collections ] && return 0
  ansible-galaxy collection install -r hosts/ansible/requirements.yml -p hosts/ansible/collections >/dev/null
}

check_ansible() {
  collections
  local playbook
  for playbook in hosts/ansible/playbooks/*.yml; do
    (cd hosts/ansible && ansible-playbook --syntax-check -i localhost, "${playbook#hosts/ansible/}")
  done
  (cd hosts/ansible && ansible-lint --project-dir . -c "$here/ansible-lint.yml" playbooks roles)
}

check_manifests() {
  collections
  local path url sum role template out extra
  # Pinned schemas, each checked against its SHA-256.
  while read -r path url sum; do
    case $path in ''|'#'*) continue ;; esac
    mkdir -p "$work/schemas/$(dirname "$path")"
    curl -fsSL -o "$work/schemas/$path" "$url"
    echo "$sum  $work/schemas/$path" | sha256sum --check --quiet
  done < "$here/manifests/schemas.lock"
  mkdir -p "$work/rendered"
  while read -r role template out extra; do
    case $role in ''|'#'*) continue ;; esac
    (cd hosts/ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i localhost, \
      "$here/manifests/render.yml" -e role="$role" -e template="$template" \
      -e dest="$work/rendered/$out" -e "$extra" >/dev/null)
  done < "$here/manifests/cases.txt"
  kubeconform -strict -summary -output text \
    -schema-location "$work/schemas/core/{{ .ResourceKind }}{{ .KindSuffix }}.json" \
    -schema-location "$work/schemas/crd/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json" \
    "$work/rendered"
}

check_scripts() {
  # Warnings and errors fail; style notes do not (an agent pick, STD-0005).
  git ls-files -z -- '*.sh' | xargs -0 shellcheck --severity=warning
  actionlint -shellcheck="$(command -v shellcheck)"
}

case "${1:-all}" in
  terraform) check_terraform ;;
  ansible) check_ansible ;;
  manifests) check_manifests ;;
  scripts) check_scripts ;;
  all) check_terraform; check_ansible; check_manifests; check_scripts ;;
  *) echo "usage: $0 [terraform|ansible|manifests|scripts|all]" >&2; exit 2 ;;
esac
