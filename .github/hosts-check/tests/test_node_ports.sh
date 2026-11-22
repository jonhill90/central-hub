#!/usr/bin/env bash
# k8s_node opens tcp 9100 (node-exporter) in its defaults and its argument spec: Prometheus scrapes every node's own address, and the
# rebuild never runs k8s-observability.yml, which also opens it (prod resume 6, 2026-11-22: the control plane's target was down).
set -u
root=$(cd "$(dirname "$0")/../../.." && pwd); fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
d=$root/hosts/ansible/roles/k8s_node
python3 -I - "$d" <<'PY' && ok "1. 9100/tcp is in k8s_node_ports, in the defaults and in the argument spec, and the two lists are equal" || bad "1. ports differ or lack 9100/tcp"
import re, sys
d = sys.argv[1]
a = re.search(r"^k8s_node_ports: \[(.*)\]", open(d + "/defaults/main.yml").read(), re.M).group(1).split(", ")
b = re.search(r"k8s_node_ports:\n.*?default: \[(.*?)\]", open(d + "/meta/argument_specs.yml").read(), re.S).group(1).split(", ")
sys.exit(0 if a == b and "9100/tcp" in a else 1)
PY
exit $fail
