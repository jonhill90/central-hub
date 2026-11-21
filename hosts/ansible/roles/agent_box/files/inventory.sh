#!/bin/bash
# /usr/local/libexec/agent-box/inventory.sh: the one reader and editor of the lab's private inventory on the agent box
# (docs/specs/2026-11-private-values-on-the-box.md). It runs as user `invops` through sudo, so the session that asks for it
# never reads a value. The working copy is /etc/agent-keys/inventory/hosts.yml, mode 0600 in a 0700 folder.
#   inventory.sh set <scope.variable> [<cmsg_...>] < value   one listed value, as YAML or JSON on standard input
#   inventory.sh get <scope.variable>                         prints the value's type and the first 12 hex digits of its SHA-256
#   inventory.sh names                                        prints the key paths the working copy holds, never a value
#   inventory.sh diff                                         the last change, with every address, name and email replaced
#   inventory.sh log                                          the last 5 lines of the change log (paths, classes, hash prefixes)
#   inventory.sh view <proxmox|opnsense|k8s_nodes>            for the wrapper users only: the group and all.vars, as an inventory
#   inventory.sh import prod|guard                            first fill: the prod or guard copy becomes the working copy
#   inventory.sh import-compare                               the key paths where the prod and guard copies differ
# A key path is accepted only if the reviewed list editable-values.yml (installed beside this file, root-owned) names it, with a
# type the value must pass and a class. The classes firewall, tailnet, access and money need the standing go's message ID after the path.
# No value is printed by any action but `view`. The working copy is written from parsed data, so a `set` drops the comments the
# example file carries; the values stay. The role gives this user read access to the two import sources and installs this file
# and the list (the wiring is a later change, see the spec's "Points to").
set -euo pipefail
umask 077

usage() {
  echo "usage: inventory set <scope.variable> [<cmsg_...>] < value | get <scope.variable> | names | diff | log | view <proxmox|opnsense|k8s_nodes> | import prod|guard | import-compare" >&2
  exit 2
}
libexec=/usr/local/libexec/agent-box
work=/var/lib/agent-box
store=/etc/agent-keys/inventory/hosts.yml
prev=/etc/agent-keys/inventory/hosts.yml.prev
logs=$work/inventory-logs
allow=$libexec/editable-values.yml
prod_src=/etc/agent-keys/prod/inventory-hosts.yml
guard_src=/etc/agent-keys-guard/inventory/hosts.yml
py=$libexec/ansible-venv/bin/python3
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

action=${1:-}
case $action in
  set) [[ $# -ge 2 && $# -le 3 ]] || usage ;;
  get | view | import) [[ $# -eq 2 ]] || usage ;;
  names | diff | log | import-compare) [[ $# -eq 1 ]] || usage ;;
  *) usage ;;
esac
[[ $action != set || -z ${3:-} || ${3:-} =~ ^cmsg_[A-Za-z0-9]{10,80}$ ]] || { echo "inventory: the message ID is cmsg_..." >&2; exit 2; }
[[ $action != view || ${2:-} =~ ^(proxmox|opnsense|k8s_nodes)$ ]] || { echo "inventory: view takes proxmox, opnsense or k8s_nodes (agent_box is the box's own limit and is not a part)" >&2; exit 2; }
[[ $action != import || ${2:-} =~ ^(prod|guard)$ ]] || usage
[[ $action != get && $action != set || ${2:-} =~ ^[a-z0-9_]+\.[a-z0-9_]+$ ]] || { echo "inventory: a key path is <scope>.<variable>, lowercase letters, digits and _" >&2; exit 2; }

code=$(cat <<'PY'
import copy, datetime, hashlib, ipaddress, json, os, re, sys, yaml

action, store, prev, logs, allow, prod_src, guard_src = sys.argv[1:8]
args = sys.argv[8:]
GROUP_HOSTS = ("proxmox", "agent_box", "opnsense")   # groups whose host names are walked; node names are never walked
SECRETISH = re.compile(r"secret|token|password|passwd|private|_key", re.I)
NAME = re.compile(r"[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?")
URL = re.compile(r"https://[a-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


def die(msg, code=1):
    print("inventory: " + msg, file=sys.stderr)
    sys.exit(code)


def load(path):
    try:
        with open(path) as f:
            d = yaml.safe_load(f)
    except OSError:
        return None
    except yaml.YAMLError:
        die("%s is not readable YAML" % os.path.basename(path))
    return d if isinstance(d, dict) else None


def sha(v):
    return hashlib.sha256(json.dumps(v, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:12]


# --- the types a value must pass ---
def is_str(x): return isinstance(x, str)
def is_int(x): return isinstance(x, int) and not isinstance(x, bool)


def ok_address(x):
    try: ipaddress.IPv4Address(x); return is_str(x)
    except ValueError: return False


def ok_cidr(x):
    try: ipaddress.IPv4Network(x, strict=False); return is_str(x) and "/" in x
    except ValueError: return False


def ok_port(x): return is_int(x) and 1 <= x <= 65535
def ok_name(x): return is_str(x) and bool(NAME.fullmatch(x))
def ok_url(x): return is_str(x) and bool(URL.fullmatch(x))
def ok_email(x): return is_str(x) and bool(EMAIL.fullmatch(x))
def ok_list(x, f, lo, hi): return isinstance(x, list) and lo <= len(x) <= hi and all(f(i) for i in x)


def ok_rule(r):
    return (isinstance(r, dict) and {"action", "source", "proto", "dport"} <= set(r) <= {"action", "source", "proto", "dport", "comment"}
            and r["action"] in ("ACCEPT", "DROP") and ok_cidr(r["source"]) and r["proto"] in ("tcp", "udp")
            and (ok_port(r["dport"]) or (is_str(r["dport"]) and r["dport"].isdigit() and ok_port(int(r["dport"]))))
            and (r.get("comment") is None or (is_str(r["comment"]) and len(r["comment"]) <= 120 and "\n" not in r["comment"])))


def check_type(entry, v):
    t = entry["type"]
    if t == "address": return ok_address(v)
    if t == "cidr": return ok_cidr(v)
    if t == "port": return ok_port(v)
    if t == "bool": return isinstance(v, bool)
    if t == "name": return ok_name(v)
    if t == "url": return ok_url(v)
    if t == "email": return ok_email(v)
    if t == "choice": return v in entry.get("values", [])
    if t == "names": return ok_list(v, ok_name, 0, 50)
    if t == "cidrs": return ok_list(v, ok_cidr, 1, 50)
    if t == "rules": return ok_list(v, ok_rule, 0, 100)
    return False


def shape(v, entry):
    """What a reviewer may read: types and counts, with every address, name and email replaced."""
    t = entry["type"] if entry else None
    if t == "bool" or isinstance(v, bool): return str(v).lower()
    if t == "port" or is_int(v): return str(v)
    if t == "choice": return repr(v)
    if t == "rules" and isinstance(v, list):
        return "[" + "; ".join("%s %s port %s source <cidr>" % (r.get("action", "?"), r.get("proto", "?"), r.get("dport", "?"))
                               if isinstance(r, dict) and r.get("action") in ("ACCEPT", "DROP") and r.get("proto") in ("tcp", "udp")
                               else "<rule>" for r in v) + "]"
    if v is None: return "unset"
    if isinstance(v, list): return "<list of %d>" % len(v)
    if isinstance(v, dict): return "<map of %d>" % len(v)
    return {"address": "<ip>", "cidr": "<cidr>", "name": "<name>", "url": "<url>", "email": "<email>"}.get(t, "<text>")


# --- where a value lives in the inventory ---
def scopes(inv):
    """(scope name, mapping) for all.vars, each group's vars and each host's vars in the walked groups."""
    out = []
    a = inv.get("all") or {}
    out.append(("all", a.setdefault("vars", {}) if isinstance(a.get("vars", {}), dict) else {}))
    def walk(children, under_hosts):
        for g, body in (children or {}).items():
            if not isinstance(body, dict): continue
            if isinstance(body.get("vars"), dict): out.append((g, body["vars"]))
            if g in GROUP_HOSTS or under_hosts:
                for h, hv in (body.get("hosts") or {}).items():
                    if isinstance(hv, dict): out.append((h, hv))
            walk(body.get("children"), under_hosts)
    walk(a.get("children"), False)
    return out


def flatten(inv):
    flat = {}
    for scope, m in scopes(inv):
        for k, v in m.items():
            flat.setdefault("%s.%s" % (scope, k), v)
    return flat


def entries():
    d = load(allow)
    if d is None: die("the list of editable values is missing or unreadable: %s" % os.path.basename(allow))
    return d.get("refused") or [], {e["path"]: e for e in d.get("entries") or []}


def entry_for(path):
    refused, ents = entries()
    var = path.split(".", 1)[1]
    if var in refused or (path not in ents and SECRETISH.search(var)): die("%s is a secret; it never goes through this wrapper" % path)
    if path not in ents: die("%s is not in the list of editable values" % path)
    return ents[path]


def write_store(inv):
    d = os.path.dirname(store)
    os.makedirs(d, mode=0o700, exist_ok=True)
    tmp = store + ".part"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("---\n# The working copy of the lab's private inventory, written by inventory.sh (comments are not kept).\n")
        yaml.safe_dump(inv, f, sort_keys=False, default_flow_style=False, width=1000)
    os.replace(tmp, store)


def find_scope(inv, scope):
    for s, m in scopes(inv):
        if s == scope: return m
    return None


if action == "names":
    inv = load(store) or die("no working copy yet (run inventory import)")
    for p in sorted(flatten(inv)): print(p)
elif action == "get":
    entry = entry_for(args[0])
    inv = load(store) or die("no working copy yet (run inventory import)")
    m = find_scope(inv, args[0].split(".", 1)[0])
    var = args[0].split(".", 1)[1]
    print("%s %s" % (entry["type"], sha(m[var]) if m is not None and var in m else "unset"))
elif action == "set":
    path = args[0]; ref = args[1] if len(args) > 1 else ""
    entry = entry_for(path)
    if entry["class"] != "plain" and not ref: die("%s is class %s: give the standing go's message ID after the path" % (path, entry["class"]), 2)
    raw = sys.stdin.read(65537)
    if len(raw) > 65536: die("the value is over 64 KiB; refused", 2)
    try: value = yaml.safe_load(raw)
    except yaml.YAMLError: die("the value is not YAML or JSON", 2)
    if not check_type(entry, value): die("the value does not pass type %s for %s" % (entry["type"], path), 2)
    inv = load(store) or die("no working copy yet (run inventory import)")
    scope, var = path.split(".", 1)
    m = find_scope(inv, scope)
    if m is None: die("%s: the working copy has no scope %s" % (path, scope))
    before = sha(m[var]) if var in m else "unset"
    after = sha(value)
    os.makedirs(os.path.dirname(prev), mode=0o700, exist_ok=True)
    with open(prev, "w") as f: yaml.safe_dump(inv, f, sort_keys=False, default_flow_style=False, width=1000)
    os.chmod(prev, 0o600)
    m[var] = value
    write_store(inv)
    os.makedirs(logs, mode=0o700, exist_ok=True)
    line = {"time": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "path": path, "class": entry["class"],
            "relay_ref": ref or "-", "before": before, "after": after}
    with open(os.path.join(logs, "set.jsonl"), "a") as f: f.write(json.dumps(line, sort_keys=True) + "\n")
    print("inventory: set %s (class %s): %s -> %s" % (path, entry["class"], before, after))
elif action == "diff":
    cur = load(store) or die("no working copy yet (run inventory import)")
    old = load(prev)
    if old is None: die("no earlier copy to compare with (no set has run)")
    _, ents = entries()
    a, b = flatten(old), flatten(cur)
    n = 0
    for p in sorted(set(a) | set(b)):
        if p in a and p in b and a[p] == b[p]: continue
        e = ents.get(p)
        print("%s: %s -> %s" % (p, shape(a[p], e) if p in a else "unset", shape(b[p], e) if p in b else "unset")); n += 1
    print("inventory: %d path(s) differ" % n)
elif action == "log":
    p = os.path.join(logs, "set.jsonl")
    if not os.path.exists(p): die("no set has been logged yet")
    print("".join(open(p).readlines()[-5:]), end="")
elif action == "view":
    inv = load(store) or die("no working copy yet (run inventory import)")
    _, ents = entries()
    part = args[0]
    kids = ((inv.get("all") or {}).get("children") or {})
    if part not in kids: die("the working copy has no group %s" % part)
    out = {"all": {"children": {part: copy.deepcopy(kids[part])}}}
    v = (inv.get("all") or {}).get("vars")
    if v: out["all"]["vars"] = copy.deepcopy(v)
    yaml.safe_dump(out, sys.stdout, sort_keys=False, default_flow_style=False, width=1000)
elif action == "import":
    src = prod_src if args[0] == "prod" else guard_src
    inv = load(src) or die("the %s copy is missing or unreadable" % args[0])
    if os.path.exists(store): die("a working copy already exists; import fills a first copy only")
    write_store(inv)
    print("inventory: working copy written from the %s copy (%d key paths)" % (args[0], len(flatten(inv))))
elif action == "import-compare":
    p, g = load(prod_src), load(guard_src)
    if p is None or g is None: die("the prod or guard copy is missing or unreadable")
    a, b = flatten(p), flatten(g)
    n = 0
    for k in sorted(set(a) | set(b)):
        if k not in a: print("only in guard: " + k); n += 1
        elif k not in b: print("only in prod: " + k); n += 1
        elif a[k] != b[k]: print("differs: " + k); n += 1
    print("inventory: %d key path(s) differ between the prod and guard copies" % n)
PY
)
exec "$py" -I -c "$code" "$action" "$store" "$prev" "$logs" "$allow" "$prod_src" "$guard_src" "${@:2}"
