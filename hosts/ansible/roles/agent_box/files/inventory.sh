#!/bin/bash
# /usr/local/libexec/agent-box/inventory.sh: the one reader and editor of the lab's private inventory on the agent box
# (docs/specs/2026-11-private-values-on-the-box.md). It runs as user `invops` through sudo, so the session that asks for it
# never reads a value. The working copy is /etc/agent-keys-inventory/hosts.yml, mode 0600 in a 0700 folder of this user.
#   inventory.sh set <scope.variable> [<cmsg_...>] < value   one listed value, as YAML or JSON on standard input
#   inventory.sh get <scope.variable>                         prints the value's type and a 12-hex tag: HMAC-SHA-256 of the value under this user's own key
#   inventory.sh names                                        prints the key paths the working copy holds, never a value
#   inventory.sh diff                                         the key paths the last change touched, each as `changed`; never a value or a shape
#   inventory.sh log                                          the last 5 lines of the change log (paths, classes, message IDs, tags)
#   inventory.sh view <proxmox|opnsense|k8s_nodes>            for the wrapper users only: the group and all.vars, as an inventory
#   inventory.sh import prod|guard                            first fill: the prod or guard copy becomes the working copy (refused once a copy exists)
#   inventory.sh import-compare                               the key paths where the prod and guard copies differ
#   inventory.sh seal                                         encrypts the working copy to the bundle's recipients (the box's and, if set, the Mac's age public keys) into
#                                                             the sealed folder, where the keys user's daily bundle picks it up; set and import run it after they write
# A key path is accepted only if the reviewed list editable-values.yml (installed beside this file, root-owned) names it, with a
# type the value must pass and a class. The classes firewall, tailnet, access and money need the standing go's message ID after the path.
# No value is printed by any action but `view`. The tag key (tag.key beside the working copy, mode 0600, made on first use, never printed)
# keeps a tag from being brute-forced the way a plain hash of a short value can be; deleting the key changes every tag. The working copy
# is written from parsed data, so a `set` drops the comments the example file carries; the values stay. The agent_box role installs this
# file, the list and the user (tasks/inventory_job.yml, tasks/main.yml). The two old copies are read through two exact sudo lines of the
# role's sudoers file (templates/sudoers.j2), as their owners; this user has no other access to either. A session runs everything
# but `view` and no consumer reads this copy yet: each switches to `view` in its own change.
set -euo pipefail
umask 077

usage() {
  echo "usage: inventory set <scope.variable> [<cmsg_...>] < value | get <scope.variable> | names | diff | log | seal | view <proxmox|opnsense|k8s_nodes> | import prod|guard | import-compare" >&2
  exit 2
}
libexec=/usr/local/libexec/agent-box
work=/var/lib/agent-box-inventory
store=/etc/agent-keys-inventory/hosts.yml
tagkey=/etc/agent-keys-inventory/tag.key
prev=/etc/agent-keys-inventory/hosts.yml.prev
recipients=/etc/agent-keys-inventory/recipients.txt   # public age keys, one per line; the role writes it from the secrets bundle's settings
sealed=/etc/agent-keys-inventory-sealed/inventory.sops.json   # the folder is this user's, group keys, so the keys user's bundle can read the file
sops=$libexec/sops
logs=$work/logs
allow=$libexec/editable-values.yml
# The two old copies are read as their owners, with the exact commands the sudoers file allows this user (no path is an argument).
prod_cmd=(sudo -n -u keys /usr/bin/cat /etc/agent-keys/prod/inventory-hosts.yml)
guard_cmd=(sudo -n -u guardops /usr/bin/cat /etc/agent-keys-guard/inventory/hosts.yml)
py=$libexec/ansible-venv/bin/python3
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

action=${1:-}
case $action in
  set) [[ $# -ge 2 && $# -le 3 ]] || usage ;;
  get | view | import) [[ $# -eq 2 ]] || usage ;;
  names | diff | log | seal | import-compare) [[ $# -eq 1 ]] || usage ;;
  *) usage ;;
esac
[[ $action != set || -z ${3:-} || ${3:-} =~ ^cmsg_[A-Za-z0-9]{10,80}$ ]] || { echo "inventory: the message ID is cmsg_..." >&2; exit 2; }
[[ $action != view || ${2:-} =~ ^(proxmox|opnsense|k8s_nodes)$ ]] || { echo "inventory: view takes proxmox, opnsense or k8s_nodes (agent_box is the box's own limit and is not a part)" >&2; exit 2; }
[[ $action != import || ${2:-} =~ ^(prod|guard)$ ]] || usage
[[ $action != get && $action != set || ${2:-} =~ ^[a-z0-9_]+\.[a-z0-9_]+$ ]] || { echo "inventory: a key path is <scope>.<variable>, lowercase letters, digits and _" >&2; exit 2; }

prod_src=/dev/null guard_src=/dev/null
if [[ $action == import || $action == import-compare ]]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  if [[ $action == import-compare || ${2:-} == prod ]]; then "${prod_cmd[@]}" > "$tmp/prod.yml" || { echo "inventory: could not read the prod copy" >&2; exit 1; }; prod_src=$tmp/prod.yml; fi
  if [[ $action == import-compare || ${2:-} == guard ]]; then "${guard_cmd[@]}" > "$tmp/guard.yml" || { echo "inventory: could not read the guard copy" >&2; exit 1; }; guard_src=$tmp/guard.yml; fi
fi

code=$(cat <<'PY'
import copy, datetime, hashlib, hmac, ipaddress, json, os, re, sys, yaml

action, store, prev, logs, allow, prod_src, guard_src, tagkey = sys.argv[1:9]
args = sys.argv[9:]
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


def key():
    """The tag key: 32 random bytes, mode 0600, made on first use. Never printed or logged."""
    try:
        with open(tagkey, "rb") as f:
            k = f.read()
        if len(k) >= 32: return k
        die("the tag key file is too short; remove it to make a new one (every tag changes)")
    except OSError:
        pass
    os.makedirs(os.path.dirname(tagkey), mode=0o700, exist_ok=True)
    try:
        fd = os.open(tagkey, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return key()
    with os.fdopen(fd, "wb") as f:
        f.write(os.urandom(32))
    return key()


def sha(v):
    """A 12-hex tag of a value: HMAC-SHA-256 under the tag key, so a short or guessable value can't be recovered from it."""
    return hmac.new(key(), json.dumps(v, sort_keys=True, separators=(",", ":")).encode(), hashlib.sha256).hexdigest()[:12]


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
    a, b = flatten(old), flatten(cur)
    n = 0
    for p in sorted(set(a) | set(b)):
        if p in a and p in b and a[p] == b[p]: continue
        print("%s: changed" % p); n += 1
    print("inventory: %d path(s) changed since the copy before the last set" % n)
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
# Seals the working copy to the bundle's recipients with sops (the keys user's bundle carries the result; this user holds no identity,
# so it can not open what it makes). A failure here leaves the change made and says so.
seal_it() {
  local list='' r tmp
  [[ -s $recipients ]] || { echo "inventory: $recipients is missing or empty, so the copy is not sealed (the role writes it when the secrets bundle is set)" >&2; return 3; }
  while IFS= read -r r; do
    [[ -z $r ]] && continue
    [[ $r =~ ^age1[0-9a-z]{58}$ ]] || { echo "inventory: a line of $recipients is not an age recipient; not sealed" >&2; return 3; }
    list+=${list:+,}$r
  done < "$recipients"
  [[ -n $list ]] || { echo "inventory: $recipients holds no recipient; not sealed" >&2; return 3; }
  tmp=$(mktemp "$sealed.XXXXXX") || { echo "inventory: can not write in the sealed folder; not sealed" >&2; return 3; }
  if "$sops" encrypt --input-type binary --output-type json --age "$list" --output "$tmp" "$store" 2>/dev/null && [[ -s $tmp ]]; then
    chmod 0640 "$tmp" && mv -f -- "$tmp" "$sealed" && echo "inventory: sealed copy written for the bundle" && return 0
  fi
  rm -f -- "$tmp"; echo "inventory: sops could not seal the copy; not sealed" >&2; return 3
}

if [[ $action == seal ]]; then
  [[ -f $store ]] || { echo "inventory: no working copy yet (run inventory import)" >&2; exit 1; }
  seal_it; exit $?
fi
"$py" -I -c "$code" "$action" "$store" "$prev" "$logs" "$allow" "$prod_src" "$guard_src" "$tagkey" "${@:2}"
if [[ $action == set || $action == import ]]; then
  seal_it || { echo "inventory: the change is made; run inventory seal after the cause is fixed" >&2; exit 3; }
fi
