#!/usr/bin/python3 -I
"""vps-apply: the VPS apps host applies its own reviewed setup and makes its own secrets (D-0046).

Installed by the vps_app_host role as /usr/local/sbin/vps-apply, root-owned. User `deploy` may run it
through sudo with these first arguments only (/etc/sudoers.d/vps-apply):

  vps-apply host <commit>     check out <commit> of central-hub, which must be on main, and run
                              hosts/ansible/playbooks/vps-app-host.yml on this host, locally
  vps-apply secrets           make each host secret that does not exist yet (S5)
  vps-apply secrets rotate    make every host secret again
  vps-apply status            what is applied and which secrets exist, never a value

`secrets` refuses unless SUDO_USER is `deploy`. That guards against running it by mistake; it is not a
boundary, because a root session can set SUDO_USER itself. What keeps secrets from agent sessions is the
step order: `secrets` runs at S5, only after S4 has removed root from every agent login (D-0046 rule 4).
What it prints holds no secret: commits, file names, counts and pass or fail. Full logs stay in
/var/lib/vps-apply/logs/, root only.
"""
import fcntl
import grp
import json
import os
import pwd
import re
import secrets
import socket
import subprocess
import sys
import time
from pathlib import Path

WORK = Path("/var/lib/vps-apply")
REPO = WORK / "central-hub"
LOGS = WORK / "logs"
SUMMARY = LOGS / "summary.jsonl"
REPO_URL = "https://github.com/jonhill90/central-hub.git"
PLAYBOOK = "playbooks/vps-app-host.yml"
DEPLOY_USER = "deploy"
VALKEY_SECRET = Path("/etc/valkey/vps-secret.conf")
VALKEY_PORT = 6379
OMNIROUTE_USER = "omniroute"
OMNIROUTE_SECRETS = "secrets.env"   # under ~omniroute/.config/vps-apps/
OMNIROUTE_NAMES = ("VPS_VALKEY_PASSWORD", "VPS_OMNIROUTE_API_KEY", "VPS_OMNIROUTE_WS_BRIDGE_SECRET")
USAGE = "usage: vps-apply host <40-hex commit> | secrets [rotate] | status"


def die(msg, code=1):
    print(f"vps-apply: {msg}", file=sys.stderr)
    sys.exit(code)


def record(action, commit, result):
    LOGS.mkdir(mode=0o700, parents=True, exist_ok=True)
    line = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "action": action,
            "commit": commit, "result": result}
    with SUMMARY.open("a") as f:
        f.write(json.dumps(line) + "\n")


def git(*args, log):
    return subprocess.run(["git", "-C", str(REPO), *args], check=True, stdout=log, stderr=log)


def host(commit):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        die("host needs a full 40-hex commit of central-hub main", 2)
    LOGS.mkdir(mode=0o700, parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    raw = LOGS / f"run-{stamp}.txt"
    with raw.open("w") as log:
        os.chmod(raw, 0o600)
        if not (REPO / ".git").is_dir():
            subprocess.run(["git", "clone", "--quiet", "--no-checkout", REPO_URL, str(REPO)],
                           check=True, stdout=log, stderr=log)
        git("fetch", "--quiet", "origin", "main", log=log)
        # Only reviewed code: the commit must be main's head or behind it on main.
        on_main = subprocess.run(["git", "-C", str(REPO), "merge-base", "--is-ancestor", commit, "origin/main"],
                                 stdout=log, stderr=log).returncode == 0
        if not on_main:
            record("host", commit, "refused: not on main")
            die(f"{commit[:12]} is not on central-hub main; nothing applied")
        git("checkout", "--quiet", "--detach", commit, log=log)
        inventory = WORK / "inventory.ini"
        inventory.write_text("[vps_app_host]\nlocalhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3\n")
        os.chmod(inventory, 0o600)
        env = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin", "HOME": str(WORK),
               "ANSIBLE_CONFIG": str(REPO / "hosts/ansible/ansible.cfg"), "ANSIBLE_NOCOLOR": "1"}
        rc = subprocess.run(["ansible-playbook", "-i", str(inventory), PLAYBOOK],
                            cwd=REPO / "hosts/ansible", env=env, stdout=log, stderr=log).returncode
    result = "ok" if rc == 0 else f"FAIL: ansible-playbook exit {rc}"
    record("host", commit, result)
    print(f"vps-apply: host {commit[:12]}: {result} (log {raw.name})")
    sys.exit(0 if rc == 0 else 1)


def write_secret_file(path, text, owner, group, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".new")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chown(tmp, pwd.getpwnam(owner).pw_uid, grp.getgrnam(group).gr_gid)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def read_env(path):
    out = {}
    if path.is_file():
        for line in path.read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k] = v
    return out


def make_secrets(rotate):
    if os.environ.get("SUDO_USER") != DEPLOY_USER:
        die(f"secrets runs only through sudo by {DEPLOY_USER}, after the narrowing (D-0046 S5); nothing made")
    made, kept = [], []
    # Valkey's password, in the file valkey.conf includes; readable by Valkey's group only.
    valkey_pw = None
    if VALKEY_SECRET.is_file() and not rotate:
        m = re.search(r"^requirepass (\S+)$", VALKEY_SECRET.read_text(), re.M)
        valkey_pw = m.group(1) if m else None
    if valkey_pw:
        kept.append("valkey password")
    else:
        valkey_pw = secrets.token_urlsafe(32)
        write_secret_file(VALKEY_SECRET, f"requirepass {valkey_pw}\n", "root", "valkey", 0o640)
        made.append("valkey password")
    # OmniRoute's own secrets and Valkey's password, in a file only its user reads.
    home = Path(pwd.getpwnam(OMNIROUTE_USER).pw_dir)
    path = home / ".config/vps-apps" / OMNIROUTE_SECRETS
    have = {} if rotate else read_env(path)
    want = {}
    for name in OMNIROUTE_NAMES:
        if name == "VPS_VALKEY_PASSWORD":
            want[name] = valkey_pw
        elif have.get(name):
            want[name] = have[name]
            kept.append(name)
        else:
            want[name] = secrets.token_urlsafe(32)
            made.append(name)
    if want != have:
        (home / ".config").mkdir(mode=0o700, exist_ok=True)
        os.chown(home / ".config", pwd.getpwnam(OMNIROUTE_USER).pw_uid, grp.getgrnam(OMNIROUTE_USER).gr_gid)
        path.parent.mkdir(mode=0o700, exist_ok=True)
        os.chown(path.parent, pwd.getpwnam(OMNIROUTE_USER).pw_uid, grp.getgrnam(OMNIROUTE_USER).gr_gid)
        write_secret_file(path, "".join(f"{k}={v}\n" for k, v in want.items()), OMNIROUTE_USER, OMNIROUTE_USER, 0o600)
    if "valkey password" in made:
        subprocess.run(["systemctl", "enable", "--quiet", "valkey"], check=True)
        subprocess.run(["systemctl", "restart", "valkey"], check=True)
    result = f"made {len(made)}, kept {len(kept)}"
    record("secrets rotate" if rotate else "secrets", "", result)
    print(f"vps-apply: secrets: made {', '.join(made) or 'none'}; kept {', '.join(kept) or 'none'}")


def status():
    last = None
    if SUMMARY.is_file():
        for line in SUMMARY.read_text().splitlines():
            entry = json.loads(line)
            if entry["action"] == "host" and entry["result"] == "ok":
                last = entry
    print(f"vps-apply: last good host apply: {last['commit'][:12] + ' at ' + last['time'] if last else 'none'}")
    home = Path(pwd.getpwnam(OMNIROUTE_USER).pw_dir)
    names = sorted(read_env(home / ".config/vps-apps" / OMNIROUTE_SECRETS))
    print(f"vps-apply: valkey password file: {'present' if VALKEY_SECRET.is_file() else 'absent'}")
    print(f"vps-apply: omniroute secrets: {', '.join(names) or 'none'}")
    active = subprocess.run(["systemctl", "is-active", "valkey"], capture_output=True, text=True).stdout.strip()
    print(f"vps-apply: valkey: {active}")
    if active == "active" and VALKEY_SECRET.is_file():
        print(f"vps-apply: valkey proof: {valkey_proof()}")


def valkey_ask(lines):
    with socket.create_connection(("127.0.0.1", VALKEY_PORT), timeout=5) as c:
        c.sendall("".join(f"{x}\r\n" for x in lines).encode())
        # One simple-string or error reply per command; read until all have come or the server closes.
        out = b""
        while out.count(b"\r\n") < len(lines) and (chunk := c.recv(4096)):
            out += chunk
    return out.decode(errors="replace").splitlines()


def valkey_proof():
    """No password: refused. With the password: PONG. Prints neither the password nor Valkey's answer text."""
    m = re.search(r"^requirepass (\S+)$", VALKEY_SECRET.read_text(), re.M)
    if not m:
        return "FAIL: no password in the file"
    try:
        bare = valkey_ask(["PING"])
        authed = valkey_ask([f"AUTH {m.group(1)}", "PING"])
    except OSError as e:
        return f"FAIL: {type(e).__name__}"
    refused = bool(bare) and bare[0].startswith("-NOAUTH")
    answered = authed[-1:] == ["+PONG"]
    return "pass (no password refused, password answered)" if refused and answered else \
        f"FAIL (no password refused: {refused}, password answered: {answered})"


def main(argv):
    if os.geteuid() != 0:
        die("run it through sudo", 2)
    WORK.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock = (WORK / "lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        die("another vps-apply run is going; try again when it ends")
    match argv:
        case ["host", commit]:
            host(commit)
        case ["secrets"]:
            make_secrets(rotate=False)
        case ["secrets", "rotate"]:
            make_secrets(rotate=True)
        case ["status"]:
            status()
        case _:
            die(USAGE, 2)


if __name__ == "__main__":
    main(sys.argv[1:])
