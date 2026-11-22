#!/usr/bin/env bash
# The root chart's gateway app prunes (hosts/kubernetes/home/c1/root/values.yaml): #856 renamed route key central-hub-app to hub,
# and with prune false the old HTTPRoute stayed, the app stayed OutOfSync and failed dev's `apps` stage (dev proof of 3eb64897,
# 2026-11-22) and would fail prod's `checks`. The other apps keep their own setting; only gateway is asserted here.
# Usage: .github/hosts-check/tests/test_root_gateway_prune.sh   (needs python3 with PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
if python3 -I -c '
import sys, yaml
v = yaml.safe_load(open("hosts/kubernetes/home/c1/root/values.yaml"))
g = v["apps"]["gateway"]
sys.exit(0 if g.get("prune") is True and g.get("autoSync") is True else 1)'; then
  echo "ok   1. the gateway app has autoSync and prune true"
else echo "FAIL 1. the gateway app must have autoSync true and prune true"; exit 1; fi
