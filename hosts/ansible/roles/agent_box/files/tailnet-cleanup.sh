#!/bin/bash
# /usr/local/libexec/agent-box/tailnet-cleanup.sh: remove tailnet devices that have been offline a
# long time, so rebuilt machines and finished agent sessions don't pile up (pick 214; owner's answer
# 2026-11-12 06:43 to 06:45 UTC: only tagged devices, after 7 days offline, by a daily timer on the
# agent box with its own devices-only key). It runs as user `keys`, so the session that asks for a
# plan never sees the OAuth client. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/tailnet-cleanup.sh plan
#   (run is for the timer, which runs it as `keys` without sudo)
# plan: list what run would remove, and why each other tagged device stays. Removes nothing.
# run: remove those devices, at most max_deletes of them; more than that removes none and fails.
# A device stays unless all hold: it carries one of the settings' tags; it is not connected to the
# coordination server; its last contact is older than the settings' days (at least 7); its name is
# not on the keep list. A device with no tags (a person's own) is never touched.
set -euo pipefail
umask 077

case ${1:-} in
  plan | run) action=$1 ;;
  *) echo "usage: tailnet-cleanup plan|run" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
settings=$work/tailnet-cleanup.json   # tags, keep, days, max_deletes: written by the agent_box role
client=$keys/tailnet-cleanup.env      # TS_OAUTH_CLIENT_ID, TS_OAUTH_CLIENT_SECRET (scope devices:core)
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

[[ -f $settings ]] || { echo "tailnet-cleanup: $settings is missing; set agent_box_tailnet_cleanup in the inventory and run the agent_box role" >&2; exit 1; }
[[ -f $client ]] || { echo "tailnet-cleanup: $client is missing; put it there through the keys wrapper (docs/runbooks/set-up-the-agent-box.md, 'Remove old tailnet devices')" >&2; exit 1; }

# Python's standard library only. The client secret and the access token stay in this process:
# never in an argument, an environment variable or a file of their own.
exec python3 -I - "$action" "$settings" "$client" <<'PY'
import datetime, json, sys, urllib.error, urllib.parse, urllib.request

action, settings_file, client_file = sys.argv[1:4]
API = "https://api.tailscale.com/api/v2"

def die(msg):
    print("tailnet-cleanup: " + msg, file=sys.stderr)
    sys.exit(1)

s = json.load(open(settings_file))
tags = set(s.get("tags") or [])
keep = {k.lower() for k in (s.get("keep") or [])}
days = int(s.get("days", 7))
max_deletes = int(s.get("max_deletes", 5))
# The same limits the agent_box role checks, again here, so a hand-edited file can't widen them.
if not tags or not all(t.startswith("tag:") for t in tags): die("settings: tags must be a list of tag:<name>")
if not keep: die("settings: the keep list is empty; it must name every device that is never removed")
if days < 7: die("settings: days must be 7 or more")
if not 1 <= max_deletes <= 20: die("settings: max_deletes must be 1 to 20")

cid = csec = None
for line in open(client_file):
    k, _, v = line.strip().partition("=")
    if k == "TS_OAUTH_CLIENT_ID": cid = v.strip().strip('"')
    if k == "TS_OAUTH_CLIENT_SECRET": csec = v.strip().strip('"')
if not cid or not csec: die(client_file + " needs TS_OAUTH_CLIENT_ID and TS_OAUTH_CLIENT_SECRET")

def call(method, url, data=None, token=None):
    req = urllib.request.Request(url, data=data, method=method)
    if token: req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read()
    except urllib.error.HTTPError as e:
        # The status and the API's message, never a token or a secret.
        try: m = json.loads(e.read()).get("message", "")
        except Exception: m = ""
        die("%s %s: HTTP %d %s" % (method, url.split("?")[0], e.code, m))
    except urllib.error.URLError as e:
        die("%s %s: %s" % (method, url.split("?")[0], e.reason))
    return json.loads(body) if body.strip() else {}

token = call("POST", API + "/oauth/token", urllib.parse.urlencode(
    {"client_id": cid, "client_secret": csec, "grant_type": "client_credentials"}).encode()).get("access_token")
if not token: die("the OAuth token endpoint gave no access token")
del csec

devices = call("GET", API + "/tailnet/-/devices?fields=all", token=token).get("devices")
if devices is None: die("the device list has no devices field")

now = datetime.datetime.now(datetime.timezone.utc)
cutoff = now - datetime.timedelta(days=days)
remove, stay = [], []
for d in devices:
    name = (d.get("name") or "").split(".")[0].lower()
    host = (d.get("hostname") or "").lower()
    label = name or host or d.get("nodeId", "?")
    dtags = set(d.get("tags") or [])
    seen = d.get("lastSeen")
    if not dtags & tags:
        continue                                   # untagged or other tags: not ours to judge
    if name in keep or host in keep:
        stay.append((label, "on the keep list")); continue
    if d.get("connectedToControl") or not seen:
        stay.append((label, "online")); continue
    try:
        last = datetime.datetime.fromisoformat(seen.replace("Z", "+00:00"))
    except ValueError:
        stay.append((label, "last contact unreadable")); continue
    if last > cutoff:
        stay.append((label, "seen %s" % last.strftime("%Y-%m-%d"))); continue
    if not d.get("nodeId"):
        stay.append((label, "no node id")); continue
    remove.append((label, d["nodeId"], last.strftime("%Y-%m-%d")))

for label, why in sorted(stay):
    print("stays:  %s (%s)" % (label, why))
for label, _, last in sorted(remove):
    print("remove: %s (offline since %s)" % (label, last))
print("tailnet-cleanup: %d to remove, %d tagged devices stay, %d devices in the tailnet" % (len(remove), len(stay), len(devices)))

if action == "plan" or not remove:
    sys.exit(0)
if len(remove) > max_deletes:
    die("%d devices to remove is more than max_deletes (%d); removed none. Check the list with plan, then remove them by hand or raise the limit" % (len(remove), max_deletes))
for label, node, _ in remove:
    call("DELETE", API + "/device/" + urllib.parse.quote(node, safe=""), token=token)
    print("removed: " + label)
PY
