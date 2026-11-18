#!/usr/bin/env bash
# The apps' secrets in OpenBao (plan step 8a, D-0058 rule 8): the three sides that must name the same keys agree.
#   1. With store openbao, every ExternalSecret of apps alerts, monitoring-extras and share-pod reads key c1/<name>,
#      property value: the path and key `secrets-store put-apps` writes for each <name>=<value> line of the
#      secret-source file (hosts/ansible/roles/agent_box/files/secrets-store.sh, put_apps: kv put "c1/$name" value).
#   2. Dev's secret-source file, which the dev rebuild makes (files/rebuild.sh, ssfile), has a line for every name the
#      apps on dev read. share-pod's is left out: its ExternalSecret exists only where shareTarget is set, and dev
#      sets none (root values.yaml, shareTarget).
#   3. The runbook's list of the secrets read through store c1 (docs/runbooks/set-up-the-secrets-store.md, "The apps'
#      secrets") names exactly the keys the charts read.
# Identity's keys (c1/identity) are checked by test_identity_external_secrets.sh, and the DNS-01 token's
# (c1/cloudflare-api-token) by the k8s_certs role's own reference to the path put-apps writes.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

apps=$src/hosts/kubernetes/home/c1/apps
helm template alerts "$apps/alerts" --namespace alerts --set zone=example.com --set auth.store=openbao > "$t/r.yaml"
helm template monitoring-extras "$apps/monitoring-extras" --namespace monitoring \
  --set ntfy.store=openbao --set heartbeat.store=openbao >> "$t/r.yaml"
helm template share-pod "$apps/share-pod" --namespace share-pod --set target=192.0.2.5:22 \
  --set authKey.store=openbao >> "$t/r.yaml"

# Every (key, property) an ExternalSecret on store openbao reads, as key:property lines.
python3 -I - "$t/r.yaml" > "$t/refs" <<'PY'
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1])):
    if not d or d.get("kind") != "ExternalSecret":
        continue
    spec = d["spec"]
    if spec["secretStoreRef"]["name"] != "openbao":
        print("store:" + spec["secretStoreRef"]["name"])
    for e in spec.get("data") or []:
        print("%s:%s" % (e["remoteRef"]["key"], e["remoteRef"].get("property", "")))
PY

# 1
if [[ -s $t/refs ]] && ! grep -v -E '^c1/[a-z0-9][a-z0-9_-]*:value$' "$t/refs" >/dev/null &&
   grep -q 'kv put "c1/\$name" value' "$src/hosts/ansible/roles/agent_box/files/secrets-store.sh"; then
  ok "1. every ExternalSecret on store openbao reads c1/<name> property value, which put-apps writes ($(sort -u "$t/refs" | wc -l) keys)"
else
  bad "1. a key or property that put-apps does not write: $(grep -v -E '^c1/[a-z0-9][a-z0-9_-]*:value$' "$t/refs" | tr '\n' ' ')"
fi
sed -e 's#^c1/##' -e 's#:value$##' "$t/refs" | sort -u > "$t/read"

# 2. The names dev's rebuild writes into its secret-source file: printf '<name>=... lines and the heartbeat line.
grep -oE "^ *(printf '|\(umask 077; printf '%s\\\\n' ')[a-z0-9][a-z0-9_-]*=" "$src/hosts/ansible/roles/agent_box/files/rebuild.sh" \
  | sed -E "s/.*'([a-z0-9][a-z0-9_-]*)=$/\1/" | sort -u > "$t/dev"
grep -v '^share-pod-authkey$' "$t/read" > "$t/dev-read"
missing=$(comm -23 "$t/dev-read" "$t/dev" | tr '\n' ' ')
if [[ -s $t/dev && -z $missing ]]; then
  ok "2. dev's secret-source file has every name the apps on dev read ($(wc -l < "$t/dev-read") of $(wc -l < "$t/dev") lines)"
else
  bad "2. dev's secret-source file lacks: ${missing:-<no names found in rebuild.sh>}"
fi

# 3. The runbook's table, between "Read through store `c1` today" and "Made by Ansible".
awk '/^\*\*Read through store `c1` today/ {on=1; next} /^\*\*Made by Ansible/ {on=0} on' \
  "$src/docs/runbooks/set-up-the-secrets-store.md" | grep -oE '^\| `[a-z0-9][a-z0-9_-]*` \|' \
  | sed -E 's/^\| `([^`]*)` \|$/\1/' | sort -u > "$t/doc"
if [[ -s $t/doc ]] && cmp -s "$t/doc" "$t/read"; then
  ok "3. the runbook lists exactly the keys the charts read ($(wc -l < "$t/doc"))"
else
  bad "3. the runbook and the charts differ: only in the runbook: $(comm -23 "$t/doc" "$t/read" | tr '\n' ' '); only in the charts: $(comm -13 "$t/doc" "$t/read" | tr '\n' ' ')"
fi

exit $fail
