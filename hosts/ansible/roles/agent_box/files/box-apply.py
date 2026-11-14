#!/usr/bin/python3 -I
"""box-apply: the agent box applies its own agent_box role from reviewed main, and stops for the owner on any
change to its own limits (D-0036; docs/runbooks/apply-the-agent-box-from-itself.md). Installed root-owned by the
agent_box role when agent_box_self_apply is true; sessions start it through sudo, as root, with one argument:

  plan   Fetch main. Stop if a limit file changed since the baseline (the commit of the last full apply from the
         controller, or of the last good self-apply), then run the role in check mode and stop if it would change
         a limit path on the box. Applies nothing.
  apply  The same checks, then the role for real. After it, every limit path on the box is compared with its
         state before the run: one that changed is put back, and self-applies stop until the next full apply from
         the controller.

Its settings and its list of limits (/etc/box-apply/) and its inventory are written only by an apply from the
controller, and are limits themselves (D-0036 rules 3(f) and 7). Every run is logged to /var/log/box-apply.log.
"""

import errno
import fcntl
import fnmatch
import glob
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time

SETTINGS = "/etc/box-apply/settings.json"
LIMITS = "/etc/box-apply/limits.txt"
STATE = "/var/lib/box-apply"
LOG = "/var/log/box-apply.log"
KEEP_RUNS = 50

run = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "mode": None}


def say(msg):
    print(f"box-apply: {msg}", flush=True)


def record(result, detail=""):
    """One JSON line per run in the log, root's only."""
    run.update(result=result, detail=detail)
    fd = os.open(LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a") as f:
        f.write(json.dumps(run, sort_keys=True) + "\n")


def stop(msg, code=1):
    say(msg)
    record("stopped", msg)
    sys.exit(code)


def git(repo, *args, check=True):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if check and p.returncode != 0:
        stop(f"git {' '.join(args)} failed: {p.stderr.strip()[:300]}")
    return p


# --- The limits ---------------------------------------------------------------------------------------------

def read_limits(path):
    """limits.txt: one rule per line, '#' starts a comment.
      path <glob>            a repository file whose change stops a self-apply (fnmatch, from the repo root)
      except <glob>          a repository file the path rules leave out
      free-keys <file> <k>…  in that YAML file, only these top-level keys may change; any other change stops
      box <glob>             a file on the box compared before and after an apply, and put back if it changed
      dir <path>             a folder on the box whose owner and mode are compared and put back
      user <name>            a user whose account and groups are compared (not put back: self-applies stop)"""
    rules = {"path": [], "except": [], "free-keys": {}, "box": [], "dir": [], "user": []}
    for n, line in enumerate(open(path), 1):
        words = line.split("#", 1)[0].split()
        if not words:
            continue
        kind, rest = words[0], words[1:]
        if kind == "free-keys" and len(rest) >= 1:
            rules["free-keys"][rest[0]] = set(rest[1:])
        elif kind in rules and kind != "free-keys" and len(rest) == 1:
            rules[kind].append(rest[0])
        else:
            stop(f"{path} line {n} is not a rule: {line.strip()}")
    return rules


def limit_files(rules, changed):
    """The changed repository files that are limits."""
    hits = []
    for f in changed:
        if f in rules["free-keys"]:
            continue
        if any(fnmatch.fnmatchcase(f, g) for g in rules["path"]) and not any(
                fnmatch.fnmatchcase(f, g) for g in rules["except"]):
            hits.append(f)
    return hits


def top_level_blocks(text):
    """A YAML file's top-level keys, each with the text of its block, comment and blank lines left out. Text, not
    parsed YAML, so it needs no YAML library, and any change inside a block counts."""
    blocks, key = {}, "(before the first key)"
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#") or line.strip() == "---":
            continue
        if not line[0].isspace() and ":" in line and not line.startswith("-"):
            key = line.split(":", 1)[0].strip()
        blocks.setdefault(key, []).append(line.rstrip())
    return {k: "\n".join(v) for k, v in blocks.items()}


# A free key's new value must be a plain literal, never Jinja or a reference to another variable: a SHA-256 is 64
# lowercase hex digits, anything else free is a version made of digits and dots.
FREE_VALUE = {"sha256": re.compile(r"[0-9a-f]{64}"), "version": re.compile(r"[0-9][0-9.]*")}


def free_value_ok(key, block):
    """True if a free key's block is one line, `key: value`, and value (quotes taken off) is a plain literal."""
    lines = block.splitlines()
    if len(lines) != 1 or not lines[0].startswith(key + ":"):
        return False
    value = lines[0].split(":", 1)[1].split(" #", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        value = value[1:-1]
    kind = "sha256" if key.endswith("_sha256") else "version"
    return FREE_VALUE[kind].fullmatch(value) is not None


def limit_keys(rules, repo, base, new, changed):
    """For each free-keys file that changed: the top-level keys that changed and are not free, and the free keys
    whose new value is not a plain literal."""
    hits = []
    for f, free in rules["free-keys"].items():
        if f not in changed:
            continue
        old, cur = (top_level_blocks(git(repo, "show", f"{rev}:{f}", check=False).stdout) for rev in (base, new))
        for k in sorted(set(old) | set(cur)):
            if old.get(k) == cur.get(k):
                continue
            if k not in free:
                hits.append(f"{f}: {k}")
            elif k not in cur or not free_value_ok(k, cur[k]):
                hits.append(f"{f}: {k} (a free key's value must be a plain literal)")
    return hits


# --- The box's limit paths, before and after ----------------------------------------------------------------

def box_files(rules):
    paths = set()
    for g in rules["box"]:
        paths.update(p for p in glob.glob(g) if os.path.isfile(p) or os.path.islink(p))
    return sorted(paths)


def users(rules):
    out = {}
    for u in rules["user"]:
        a = subprocess.run(["getent", "passwd", u], capture_output=True, text=True).stdout.strip()
        g = subprocess.run(["id", u], capture_output=True, text=True).stdout.strip()
        out[u] = f"{a} | {g}"
    return out


def snapshot(rules, where):
    """Copies of the box's limit files, with their owner and mode, and the folders' and users' state."""
    shutil.rmtree(where, ignore_errors=True)
    os.makedirs(where, mode=0o700)
    files = {}
    for i, p in enumerate(box_files(rules)):
        copy = os.path.join(where, str(i))
        try:
            # O_NOFOLLOW: a file that turns into a link after the glob is read as the link, never through it.
            fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except OSError as e:
            if e.errno not in (errno.ELOOP, errno.EMLINK):
                raise
            st = os.lstat(p)
            files[p] = {"link": os.readlink(p), "uid": st.st_uid, "gid": st.st_gid}
            continue
        with os.fdopen(fd, "rb") as fh:
            st = os.fstat(fh.fileno())
            if not stat.S_ISREG(st.st_mode):
                files[p] = {"other": stat.S_IFMT(st.st_mode), "uid": st.st_uid, "gid": st.st_gid}
                continue
            data = fh.read()
        with open(copy, "xb") as out:
            out.write(data)
        files[p] = {"copy": copy, "sha256": hashlib.sha256(data).hexdigest(),
                    "uid": st.st_uid, "gid": st.st_gid, "mode": st.st_mode & 0o7777}
    dirs = {}
    for d in rules["dir"]:
        st = os.stat(d) if os.path.isdir(d) else None
        dirs[d] = [st.st_uid, st.st_gid, st.st_mode & 0o7777] if st else None
    return {"files": files, "dirs": dirs, "users": users(rules)}


def compare(rules, before):
    after = snapshot(rules, os.path.join(STATE, "after"))
    diff = []
    for p in sorted(set(before["files"]) | set(after["files"])):
        b, a = before["files"].get(p), after["files"].get(p)
        if b is None:
            diff.append(("added", p))
        elif a is None:
            diff.append(("removed", p))
        elif {k: v for k, v in b.items() if k != "copy"} != {k: v for k, v in a.items() if k != "copy"}:
            diff.append(("changed", p))
    for d, b in before["dirs"].items():
        if after["dirs"].get(d) != b:
            diff.append(("folder", d))
    for u, b in before["users"].items():
        if after["users"].get(u) != b:
            diff.append(("user", u))
    return diff


def put_back(before, diff):
    """Puts each changed limit file and folder back as it was. Users can't be put back safely; they are reported."""
    left = []
    for kind, p in diff:
        b = before["files"].get(p) if kind != "folder" else None
        try:
            if kind == "added":
                if os.path.lexists(p):
                    os.remove(p)
            elif kind in ("changed", "removed") and "link" in b:
                if os.path.lexists(p):
                    os.remove(p)
                os.symlink(b["link"], p)
                os.lchown(p, b["uid"], b["gid"])
            elif kind in ("changed", "removed") and "copy" in b:
                # Some of these folders are the keys user's, who could plant a link at the temporary name: take
                # away whatever is there, then make it new (O_EXCL), never through a link (O_NOFOLLOW), and set
                # its owner and mode on the open file before it takes the limit file's place.
                tmp = p + ".box-apply"
                if os.path.lexists(tmp):
                    os.remove(tmp)
                with open(b["copy"], "rb") as fh:
                    data = fh.read()
                fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                try:
                    view = memoryview(data)
                    while view:
                        view = view[os.write(fd, view):]
                    os.fchown(fd, b["uid"], b["gid"])
                    os.fchmod(fd, b["mode"])
                finally:
                    os.close(fd)
                os.replace(tmp, p)
            elif kind == "folder" and before["dirs"][p]:
                uid, gid, mode = before["dirs"][p]
                os.chown(p, uid, gid)
                os.chmod(p, mode)
            else:
                left.append(f"{kind} {p}")
                continue
            if shutil.which("restorecon") and os.path.lexists(p):
                subprocess.run(["restorecon", "-F", p], capture_output=True)
        except OSError as e:
            left.append(f"{kind} {p} ({e})")
    return left


# --- The role run -------------------------------------------------------------------------------------------

def play(s, repo, check):
    """Runs the agent_box playbook on the box itself, as root, with the JSON callback; returns the parsed output."""
    folder = os.path.join(repo, "hosts/ansible")
    env = {
        "PATH": f"{os.path.dirname(s['ansible_playbook'])}:/usr/local/bin:/usr/bin:/bin",
        "HOME": STATE,
        "LANG": "C.UTF-8",
        "ANSIBLE_CONFIG": os.path.join(folder, "ansible.cfg"),
        "ANSIBLE_COLLECTIONS_PATH": s["collections"],
        "ANSIBLE_HOME": os.path.join(STATE, "ansible-home"),
        "ANSIBLE_STDOUT_CALLBACK": "ansible.builtin.json",
        "ANSIBLE_LOAD_CALLBACK_PLUGINS": "1",
        "ANSIBLE_RETRY_FILES_ENABLED": "0",
    }
    argv = [s["ansible_playbook"], "-i", s["inventory"], "playbooks/agent-box.yml",
            "--skip-tags", ",".join(s["skip_tags"]), "-e", "agent_box_self_applying=true"]
    if check:
        argv += ["--check", "--diff"]
    p = subprocess.run(argv, cwd=folder, env=env, capture_output=True, text=True)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    runs = os.path.join(STATE, "runs")
    os.makedirs(runs, mode=0o700, exist_ok=True)
    with open(os.path.join(runs, f"{stamp}-{'check' if check else 'apply'}.json"), "w") as f:
        f.write(p.stdout)
        if p.stderr:
            f.write("\n--- stderr ---\n" + p.stderr)
    for old in sorted(os.listdir(runs))[:-KEEP_RUNS]:
        os.remove(os.path.join(runs, old))
    try:
        out = json.loads(p.stdout)
    except ValueError:
        stop(f"the role's {'check' if check else 'apply'} run gave no JSON (exit {p.returncode}): "
             f"{(p.stderr or p.stdout).strip()[-300:]}")
    return p.returncode, out


def changed_results(out):
    """(task name, result) for each changed result, loop items included."""
    for pl in out.get("plays", []):
        for t in pl.get("tasks", []):
            for res in t.get("hosts", {}).values():
                for r in [res] + list(res.get("results", []) if isinstance(res.get("results"), list) else []):
                    if isinstance(r, dict) and r.get("changed"):
                        yield t.get("task", {}).get("name", "?"), r


def touched_paths(r):
    found = set()

    def walk(v):
        if isinstance(v, dict):
            for k, x in v.items():
                if k in ("dest", "path", "before_header", "after_header") and isinstance(x, str):
                    found.add(x)
                else:
                    walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
    walk({k: r.get(k) for k in ("dest", "path", "diff")})
    return found


def check_hits(rules, out):
    """Changed results in a check run that would touch a limit path, a limit folder or a limit user."""
    hits = []
    for name, r in changed_results(out):
        for p in touched_paths(r):
            if any(fnmatch.fnmatchcase(p, g) for g in rules["box"]) or p in rules["dir"]:
                hits.append(f"{name}: {p}")
        if r.get("name") in rules["user"] and ("uid" in r or "groups" in r or "shell" in r):
            hits.append(f"{name}: user {r['name']}")
    return sorted(set(hits))


def failures(out):
    stats = out.get("stats", {})
    return sum(v.get("failures", 0) + v.get("unreachable", 0) for v in stats.values())


# --- Main ---------------------------------------------------------------------------------------------------

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("plan", "apply"):
        print("usage: box-apply plan|apply", file=sys.stderr)
        sys.exit(2)
    mode = run["mode"] = sys.argv[1]
    os.umask(0o077)
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    lock = open(os.path.join(STATE, "lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        stop("another box-apply run is going; try again when it ends")

    s = json.load(open(SETTINGS))
    rules = read_limits(LIMITS)
    if os.path.exists(os.path.join(STATE, "stopped")):
        stop("self-applies are stopped: an earlier apply changed a limit and it was put back "
             f"({open(os.path.join(STATE, 'stopped')).read().strip()}). The next full apply from the controller ends this.")
    try:
        base = open(os.path.join(STATE, "baseline")).read().strip()
    except OSError:
        stop("no baseline: run the agent_box role in full from the controller first (it writes the baseline)")

    repo = os.path.join(STATE, "central-hub")
    if not os.path.isdir(os.path.join(repo, ".git")):
        subprocess.run(["git", "clone", "--quiet", "--no-checkout", s["repo_url"], repo], check=True)
    git(repo, "remote", "set-url", "origin", s["repo_url"])
    git(repo, "fetch", "--quiet", "origin", "main")
    new = git(repo, "rev-parse", "FETCH_HEAD").stdout.strip()
    run.update(base=base, new=new)
    if git(repo, "cat-file", "-e", f"{base}^{{commit}}", check=False).returncode != 0:
        stop(f"the baseline {base[:8]} is not a commit on main; run the role in full from the controller")
    if git(repo, "merge-base", "--is-ancestor", base, new, check=False).returncode != 0:
        stop(f"main {new[:8]} does not descend from the baseline {base[:8]}; run the role in full from the controller")
    git(repo, "checkout", "--quiet", "--detach", "--force", new)
    git(repo, "clean", "-ffdxq")
    say(f"main {new[:8]}, baseline {base[:8]}")

    changed = [f for f in git(repo, "diff", "--name-only", "--no-renames", "-z", base, new).stdout.split("\0") if f]
    hits = limit_files(rules, changed) + limit_keys(rules, repo, base, new, changed)
    if hits:
        stop("a limit changed since the baseline, so this waits for the owner's go and an apply from the "
             "controller (D-0036 rule 6): " + "; ".join(hits), code=3)
    say(f"{len(changed)} file(s) changed since the baseline, none of them a limit")

    rc, out = play(s, repo, check=True)
    if failures(out) or rc not in (0, 2):
        stop(f"the check run failed (exit {rc}); nothing applied. Its output is in {STATE}/runs/")
    hits = check_hits(rules, out)
    if hits:
        stop("the check run would change a limit on the box, so nothing is applied: " + "; ".join(hits), code=3)
    would = sorted({name for name, _ in changed_results(out)})
    say(f"check run: {len(would)} task(s) would change: " + ("; ".join(would) if would else "none"))
    if mode == "plan":
        record("planned", f"{len(would)} task(s) would change")
        return

    before = snapshot(rules, os.path.join(STATE, "before"))
    rc, out = play(s, repo, check=False)
    diff = compare(rules, before)
    if diff:
        left = put_back(before, diff)
        what = "; ".join(f"{k} {p}" for k, p in diff)
        with open(os.path.join(STATE, "stopped"), "w") as f:
            f.write(f"{run['time']} at {new[:8]}: {what}\n")
        stop(f"the apply changed a limit on the box: {what}. Put back"
             + (f", except: {'; '.join(left)}" if left else "")
             + ". Self-applies are stopped until the next full apply from the controller.", code=4)
    if failures(out) or rc != 0:
        stop(f"the apply failed (exit {rc}); the baseline stays {base[:8]}. Its output is in {STATE}/runs/")
    with open(os.path.join(STATE, "baseline.new"), "w") as f:
        f.write(new + "\n")
    os.replace(os.path.join(STATE, "baseline.new"), os.path.join(STATE, "baseline"))
    done = sorted({name for name, _ in changed_results(out)})
    say(f"applied {new[:8]}: {len(done)} task(s) changed" + (": " + "; ".join(done) if done else ""))
    record("applied", f"{len(done)} task(s) changed")


if __name__ == "__main__":
    main()
