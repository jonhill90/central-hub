#!/usr/bin/env bash
# The agent box's c1-read wrapper (hosts/ansible/roles/agent_box/files/c1-read.sh): read verbs pass,
# and every flag that picks other credentials or opens a local file is refused before kubectl runs.
# Runs a copy with a fake kubectl that prints its arguments.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/ansible/roles/agent_box/files/c1-read.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/work"
printf 'apiVersion: v1\nkind: Config\n' > "$t/config"
printf '#!/bin/sh\necho "kubectl $*"\n' > "$t/kubectl"
chmod +x "$t/kubectl"
sed -e "s|^work=.*|work=$t/work|" -e "s|^config=.*|config=$t/config|" -e "s|^kubectl=.*|kubectl=$t/kubectl|" "$src" > "$t/c1-read.sh"
fail=0
pass() { if out=$(bash "$t/c1-read.sh" "$@" 2>&1) && [[ $out == "kubectl --kubeconfig $t/config --request-timeout=30s $*" ]]; then echo "ok   passes: $*"; else echo "FAIL should pass: $* -> $out"; fail=1; fi; }
refuse() { if out=$(bash "$t/c1-read.sh" "$@" 2>&1); then echo "FAIL should refuse: $* -> $out"; fail=1; elif [[ $out == kubectl* ]]; then echo "FAIL ran kubectl: $*"; fail=1; else echo "ok   refuses: $*"; fi; }

pass get pods -A
pass get pods -A -o wide
pass get pods -ojson
pass get pods -n kube-system -l app=coredns
pass describe node n1
pass logs -n argocd deploy/argocd-server --tail 50
pass logs -p -c main pod-1
pass get --raw /readyz
pass auth can-i --list
pass version
pass api-resources

refuse
refuse apply -f x.yaml
refuse delete pod x
refuse exec -it pod -- sh
refuse edit deploy x
refuse auth reconcile -f x
refuse get secrets --kubeconfig /etc/agent-keys/other
refuse get pods --kubeconfig=/etc/agent-keys/other
refuse get pods --context other
refuse get pods --token abc
refuse get pods --as system:admin
refuse get pods --server https://example.invalid
refuse get pods -s https://example.invalid
refuse get pods --insecure-skip-tls-verify
refuse get -f /etc/agent-keys/x
refuse get -Af /etc/agent-keys/x
refuse get --filename=/etc/agent-keys/x
refuse get -k /etc/agent-keys
refuse get pods -o go-template-file=/etc/agent-keys/x
refuse get pods -o jsonpath-file=/etc/agent-keys/x
refuse get pods --template /etc/agent-keys/x
refuse get pods --kuberc /tmp/x
refuse get pods --cache-dir /tmp/x
refuse get pods --log-file /tmp/x
refuse get pods --profile cpu
exit $fail
