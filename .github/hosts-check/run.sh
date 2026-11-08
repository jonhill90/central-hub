#!/usr/bin/env bash
# Run the hosts checks (STD-0005). CI runs the same commands.
# Usage: .github/hosts-check/run.sh [terraform|ansible|manifests|identity|scripts|backup|all]   (default: all)
# Needs: python3 with requirements.txt installed; tofu, tflint, kubeconform and helm on PATH, or
# TOOLS=<dir> holding them (install-tools.sh builds them); for ansible and manifests, the
# collections in hosts/ansible/requirements.yml (this script installs them when missing); for
# identity, docker.
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
  # Galaxy sometimes answers without its results list, and ansible-galaxy then keeps that broken
  # answer in its cache (seen in CI on 2026-11-08), so each try skips the cache and waits longer.
  local try
  for try in 1 2 3 4 5; do
    ansible-galaxy collection install --no-cache -r hosts/ansible/requirements.yml \
      -p hosts/ansible/collections >/dev/null && return 0
    [ "$try" = 5 ] && return 1
    sleep $((try * 15))
  done
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
    # A branch name in the URL lets upstream change the file under the lock: only commit SHAs.
    if [[ ! $url =~ ^https://raw\.githubusercontent\.com/[^/]+/[^/]+/[0-9a-f]{40}/ ]]; then
      echo "schemas.lock: $path is not pinned to a 40-character commit SHA: $url" >&2
      return 1
    fi
    mkdir -p "$work/schemas/$(dirname "$path")"
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 15 -o "$work/schemas/$path" "$url"
    echo "$sum  $work/schemas/$path" | sha256sum --check --quiet
  done < "$here/manifests/schemas.lock"
  mkdir -p "$work/rendered"
  while read -r role template out extra; do
    case $role in ''|'#'*) continue ;; esac
    (cd hosts/ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i localhost, \
      "$here/manifests/render.yml" -e role="$role" -e template="$template" \
      -e dest="$work/rendered/$out" -e "$extra" >/dev/null)
  done < "$here/manifests/cases.txt"
  # Each cluster's root chart, rendered as Argo CD renders it, with the made-up zone (values.yml).
  local root
  for root in hosts/kubernetes/clusters/*/root; do
    [ -f "$root/Chart.yaml" ] || continue
    helm lint --quiet "$root" --set zone=example.com --set gatewayAddress=192.0.2.10
    helm template root "$root" --set zone=example.com --set gatewayAddress=192.0.2.10 > "$work/rendered/root-$(basename "$(dirname "$root")").yaml"
  done
  # Charts kept in this repository (root values `local: true`), rendered the same way.
  local chart
  for chart in hosts/kubernetes/clusters/*/apps/*/Chart.yaml; do
    [ -f "$chart" ] || continue
    chart=$(dirname "$chart")
    helm lint --quiet "$chart" --set zone=example.com --set address=192.0.2.10
    helm template "$(basename "$chart")" "$chart" --namespace "$(basename "$chart")" --set zone=example.com --set address=192.0.2.10 \
      > "$work/rendered/app-$(basename "$(dirname "$(dirname "$chart")")")-$(basename "$chart").yaml"
  done
  # c1's own alert rules: promtool checks them and runs their unit tests (rules-tests/).
  if command -v promtool >/dev/null; then
    mkdir -p "$work/rules"
    helm template x hosts/kubernetes/clusters/c1/apps/monitoring-extras -n monitoring \
      -s templates/rules.yaml | python3 -c 'import sys, yaml; d = yaml.safe_load(sys.stdin); yaml.safe_dump({"groups": d["spec"]["groups"]}, sys.stdout)' \
      > "$work/rules/c1-lab.rules.yml"
    cp "$here/rules-tests/c1-lab.test.yml" "$work/rules/"
    promtool check rules "$work/rules/c1-lab.rules.yml"
    (cd "$work/rules" && promtool test rules c1-lab.test.yml)
  else
    echo "manifests: promtool not on PATH, rule tests skipped (install-tools.sh builds it)" >&2
  fi
  # What Argo CD will apply must equal what the roles apply today (parity.txt).
  python3 "$here/parity.py" . "$work"
  kubeconform -strict -summary -output text \
    -schema-location "$work/schemas/core/{{ .ResourceKind }}{{ .KindSuffix }}.json" \
    -schema-location "$work/schemas/crd/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json" \
    "$work/rendered"
}

check_identity() {
  # Realm lab imported into a real Keycloak in a container (identity/test_realm.sh), rendered with
  # an extra user so the users loop is tested with more than the owner.
  collections
  mkdir -p "$work/identity"
  (cd hosts/ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i localhost, \
    "$here/manifests/render.yml" -e role=k8s_identity -e template=realm.yaml.j2 \
    -e dest="$work/identity/realm.yaml" \
    -e '{"k8s_identity_owner_email":"owner@example.com","k8s_identity_extra_users":[{"username":"viewer.one","groups":["lab-viewers"]}]}' >/dev/null)
  bash "$here/identity/test_realm.sh" "$work/identity/realm.yaml"
}

check_backup() {
  # The c1 backup and restore-test scripts end to end, against a real etcd and restic repository.
  bash "$here/tests/test_backup.sh"
}

check_scripts() {
  # Warnings and errors fail; style notes do not (an agent pick, STD-0005).
  git ls-files -z -- '*.sh' | xargs -0 shellcheck --severity=warning
  echo "scripts: ShellCheck passed on $(git ls-files -- '*.sh' | wc -l) scripts"
  actionlint -shellcheck="$(command -v shellcheck)"
  echo "scripts: actionlint passed on $(git ls-files -- '.github/workflows/*.yml' | wc -l) workflows"
}

case "${1:-all}" in
  terraform) check_terraform ;;
  ansible) check_ansible ;;
  manifests) check_manifests ;;
  identity) check_identity ;;
  scripts) check_scripts ;;
  backup) check_backup ;;
  all) check_terraform; check_ansible; check_manifests; check_identity; check_scripts; check_backup ;;
  *) echo "usage: $0 [terraform|ansible|manifests|identity|scripts|backup|all]" >&2; exit 2 ;;
esac
