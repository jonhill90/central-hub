#!/usr/bin/env bash
# Jellyfin's route (hosts/kubernetes/home/c1/apps/jellyfin/templates/route.yaml) must send every
# spelling of /metrics that Jellyfin's own routing would answer to the redirect, and leave the app's
# real paths alone. Renders the chart and tests the rule's pattern as Envoy applies it: a full match
# on the path without its query string. The pattern uses only syntax that RE2 and Python share.
set -euo pipefail
chart=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/kubernetes/home/c1/apps/jellyfin
helm template jellyfin "$chart" --namespace media --set zone=example.com --set address=192.0.2.10 \
  -s templates/route.yaml | python3 -I -c '
import re, sys, yaml
routes = [d for d in yaml.safe_load_all(sys.stdin) if d and d["kind"] == "HTTPRoute"]
rules = routes[0]["spec"]["rules"]
first = rules[0]
path = first["matches"][0]["path"]
assert path["type"] == "RegularExpression", path
assert first["filters"][0]["type"] == "RequestRedirect", first
assert first["filters"][0]["requestRedirect"]["path"]["replaceFullPath"] == "/", first
assert "backendRefs" not in first, first
pattern = re.compile(path["value"])
caught = ["/metrics", "/Metrics", "/METRICS", "/metrics/", "/METRICS/", "/mEtRiCs",
          "/%6Detrics", "/%6detrics", "/m%65trics", "/%6D%65%74%72%69%63%73", "/%2Fmetrics",
          "/./metrics", "/x/../metrics", "//metrics", "/metrics/.", "/metrics/x/..", "/metrics%2F"]
passed = ["/", "/web/index.html", "/web/metrics.js", "/metricsx", "/mymetrics", "/Items",
          "/System/Info/Public", "/Users/AuthenticateByName", "/socket", "/sso/OID/start/keycloak"]
fail = 0
for p in caught:
    ok = pattern.fullmatch(p) is not None
    print(("ok  " if ok else "FAIL") + " redirected: " + p)
    fail |= not ok
for p in passed:
    ok = pattern.fullmatch(p) is None
    print(("ok  " if ok else "FAIL") + " served:     " + p)
    fail |= not ok
sys.exit(fail)
'
