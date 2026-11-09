#!/usr/bin/env bash
# Write home.records.tfvars.json from the live zone, once, to adopt it (README, "Adopt the zone").
# Reads only: it lists the zone's records with the DNS token and changes nothing at Cloudflare.
# Skips cert-manager's _acme-challenge TXT records, which cert-manager makes and deletes itself.
# Usage: export-records.sh <zone name> <token file> [output file]
#   output file defaults to home.records.tfvars.json next to this script; an existing file is
#   never overwritten, because after the adoption it is the hand-edited source of the records.
set -euo pipefail
zone=${1:?usage: export-records.sh <zone name> <token file> [output file]}
token_file=${2:?usage: export-records.sh <zone name> <token file> [output file]}
out=${3:-"$(cd "$(dirname "$0")" && pwd)/home.records.tfvars.json"}
api=https://api.cloudflare.com/client/v4

[ -e "$out" ] && { echo "$out exists; move it away first" >&2; exit 1; }
token=$(tr -d '[:space:]' < "${token_file/#\~/$HOME}")
auth=(-H "Authorization: Bearer $token")

zone_id=$(curl -fsS "${auth[@]}" "$api/zones?name=$zone" |
  python3 -I -c 'import json,sys; r=json.load(sys.stdin)["result"]; assert len(r)==1, "zone not found"; print(r[0]["id"])')

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
page=1
while :; do
  curl -fsS "${auth[@]}" "$api/zones/$zone_id/dns_records?per_page=100&page=$page" > "$work/page-$page.json"
  pages=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["result_info"]["total_pages"])' "$work/page-$page.json")
  [ "$page" -ge "$pages" ] && break
  page=$((page + 1))
done

umask 077
python3 -I - "$zone" "$zone_id" "$out" "$work"/page-*.json <<'PY'
import json, re, sys
zone, zone_id, out, pages = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
# cert-manager's DNS-01 challenge records come and go on their own; they are never adopted.
rows = [r for p in pages for r in json.load(open(p))["result"] if not r["name"].startswith("_acme-challenge.")]
rows.sort(key=lambda r: (r["type"], r["name"], json.dumps(r.get("content") or r.get("data"), sort_keys=True)))
records, imports, seen = {}, {}, {}
for r in rows:
    label = "apex" if r["name"] == zone else r["name"][: -len(zone) - 1]
    base = r["type"].lower() + "-" + re.sub(r"[^a-z0-9_-]+", "-", label.lower())
    seen[base] = seen.get(base, 0) + 1
    key = base if seen[base] == 1 else f"{base}-{seen[base]}"
    rec = {"type": r["type"], "name": r["name"], "ttl": r["ttl"], "proxied": r.get("proxied", False)}
    if r.get("data"):
        rec["data"] = {k: v for k, v in r["data"].items() if k in ("priority", "weight", "port", "target", "flags", "tag", "value")}
    else:
        rec["content"] = r["content"]
    if r.get("priority") is not None and r["type"] in ("MX", "URI"):
        rec["priority"] = r["priority"]
    if r.get("comment"):
        rec["comment"] = r["comment"]
    records[key] = rec
    imports[key] = f"{zone_id}/{r['id']}"
# A key that is the first of several gets "-1", so each key names one record whatever its order.
for base, n in seen.items():
    if n > 1:
        records[base + "-1"] = records.pop(base)
        imports[base + "-1"] = imports.pop(base)
json.dump({"records": dict(sorted(records.items())), "import_ids": dict(sorted(imports.items()))}, open(out, "w"), indent=2)
print(f"{out}: {len(records)} records")
PY
