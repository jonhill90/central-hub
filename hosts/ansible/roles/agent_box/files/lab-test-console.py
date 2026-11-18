#!/usr/bin/env python3
"""Drive the lab test copy's OPNsense (VM 100 inside the copy) through its serial console, as root on the copy
(docs/runbooks/build-the-lab-test-copy.md, firstboot). The nano image has no installer and no SSH on first boot,
and its config importer waits for a key press at the console (opnsense/core 26.1.6, src/sbin/opnsense-importer), so
the console is the only way in; the October build drove it with a script as well.

  lab-test-console.py <plan.json> <command that reaches the console> ...

The command is, from the wrapper, ssh to the copy running
`socat - UNIX-CONNECT:/var/run/qemu-server/100.serial0` (VM 100's serial0 is a socket, firewall/main.tf). The plan:
  {"passwords": [...], "dir": "/root/lab-test", "files": {"<name>": "<local path>"}, "commands": [...],
   "reboot": true}
It signs in as root with the first password that works, takes menu 8 (the shell), switches to /bin/sh, sends each
file base64-encoded in short lines and checks its SHA-256 there, runs each command in that directory and stops at
the first that fails, then reboots if asked. Passwords are never printed. Standard library only.
"""
import base64
import hashlib
import json
import os
import re
import select
import subprocess
import sys
import time

LOGIN = re.compile(rb"login: *$", re.M)
PASSWORD = re.compile(rb"Password: *$", re.M)
MENU = re.compile(rb"Enter an option: *$", re.M)
BAD = re.compile(rb"Login incorrect")
SHELL = re.compile(rb"[#$%] *$", re.M)


class Console:
    def __init__(self, argv):
        self.p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.fd = self.p.stdout.fileno()
        self.buf = b""

    def send(self, text):
        self.p.stdin.write(text.encode())
        self.p.stdin.flush()

    def expect(self, patterns, timeout):
        """Wait for the first of the patterns; return its index and the text before it, consumed."""
        deadline = time.monotonic() + timeout
        while True:
            hits = [(m.start(), i, m) for i, p in enumerate(patterns) for m in [p.search(self.buf)] if m]
            if hits:
                _, i, m = min(hits, key=lambda h: (h[0], h[1]))
                before, self.buf = self.buf[:m.start()], self.buf[m.end():]
                return i, before, m
            left = deadline - time.monotonic()
            if left <= 0:
                return None, self.buf, None
            ready, _, _ = select.select([self.fd], [], [], min(left, 1.0))
            if ready:
                data = os.read(self.fd, 4096)
                if not data:
                    sys.exit("lab-test: the console closed")
                self.buf += data.replace(b"\r", b"")


def say(text):
    print(text.decode(errors="replace").rstrip("\n"), flush=True)


def sign_in(c, passwords):
    # The first boot grows the disk and runs the interface assignment's timeout before the login prompt, so wake the
    # console every 30 seconds for up to 15 minutes.
    for _ in range(30):
        c.send("\r")
        i, _, _ = c.expect([LOGIN, MENU], 30)
        if i is not None:
            break
    else:
        sys.exit("lab-test: no login prompt on the console after 15 minutes")
    if i == 1:
        return
    for pw in passwords:
        c.send("root\r")
        if c.expect([PASSWORD], 30)[0] is None:
            sys.exit("lab-test: no password prompt")
        c.send(pw + "\r")
        i, _, _ = c.expect([MENU, BAD], 90)
        if i == 0:
            return
        if i is None:
            sys.exit("lab-test: no menu after signing in")
        c.expect([LOGIN], 30)
    sys.exit("lab-test: none of the root passwords works")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    plan = json.load(open(sys.argv[1]))
    c = Console(sys.argv[2:])
    sign_in(c, plan["passwords"])
    print("lab-test: signed in on the console", flush=True)
    c.send("8\r")
    if c.expect([SHELL], 60)[0] is None:
        sys.exit("lab-test: no shell from menu 8")
    c.send("exec /bin/sh\r")
    n = 0

    def run(cmd, timeout=300, show=True):
        nonlocal n
        n += 1
        c.send(f"{cmd}; echo __LT{n}__$?\r")
        i, before, m = c.expect([re.compile(rb"__LT%d__(\d+)" % n)], timeout)
        if i is None:
            sys.exit(f"lab-test: no answer from the console to: {cmd}")
        if show:
            say(before)
        return int(m.group(1))

    d = plan["dir"]
    if run(f"mkdir -p {d} && chmod 700 {d}", show=False) != 0:
        sys.exit(f"lab-test: could not make {d}")
    for name, path in plan["files"].items():
        if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
            sys.exit(f"lab-test: bad file name {name}")
        data = open(path, "rb").read()
        b64 = base64.b64encode(data).decode()
        dest = f"{d}/{name}"
        run(f": > {dest}.b64", show=False)
        for i in range(0, len(b64), 64):
            if run(f"printf '%s\\n' {b64[i:i + 64]} >> {dest}.b64", show=False) != 0:
                sys.exit(f"lab-test: could not write {dest}")
        digest = hashlib.sha256(data).hexdigest()
        rc = run(f"openssl base64 -d -in {dest}.b64 -out {dest} && rm {dest}.b64 && chmod 600 {dest}"
                 f" && [ \"$(sha256 -q {dest})\" = {digest} ]", show=False)
        if rc != 0:
            sys.exit(f"lab-test: {dest} did not arrive whole")
        print(f"lab-test: sent {name}, sha256 {digest[:12]}", flush=True)
    for cmd in plan["commands"]:
        print(f"lab-test: console: {cmd}", flush=True)
        rc = run(f"cd {d} && {cmd}")
        if rc != 0:
            sys.exit(f"lab-test: the command failed (exit {rc}): {cmd}")
    if plan.get("reboot"):
        c.send("reboot\r")
        print("lab-test: VM 100 reboots to apply", flush=True)
    else:
        c.send("exit\r")
    # Close our side and let the connection end by itself, so the last line reaches the console before it goes:
    # socat forwards what it has, then ends on end of input. Stop it only if it hangs.
    c.p.stdin.close()
    try:
        c.p.wait(timeout=30)
    except subprocess.TimeoutExpired:
        c.p.terminate()


if __name__ == "__main__":
    main()
