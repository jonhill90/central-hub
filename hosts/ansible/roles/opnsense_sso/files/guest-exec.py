#!/usr/bin/env python3
"""Run a command in a guest through the QEMU guest agent, or write a file into it, from the Proxmox host.

  guest-exec.py <vmid> run <timeout seconds> -- <program> [argument ...]
  guest-exec.py <vmid> put <destination> <octal mode> <source file on this host>

`run` prints what the command wrote to stdout and stderr and exits with the command's own exit code, so a task can
tell "not installed" (exit 1) from "the agent is gone" (exit 125). `put` sends the bytes as base64 in pieces of 512
characters, because larger guest-agent payloads hung OPNsense's agent (docs/runbooks/set-up-lab-network-and-firewall.md
step 6, bootstrap/opnsense-backup-user.sh), then decodes them on the guest into <destination> with that mode. The
pieces go in `qm guest exec`'s arguments, so the host's process list shows them for a moment: the host has no
unprivileged users (D-0037, Consequences). Nothing from the file is printed. The guest is the firewall's VM, a FreeBSD
host with /bin/sh and openssl.
"""
import base64
import json
import re
import subprocess
import sys

PIECE = 512


def qm_exec(vm: str, timeout: int, argv: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(["qm", "guest", "exec", vm, "--timeout", str(timeout), "--", *argv],
                          capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        return 125, "", proc.stderr
    try:
        d = json.loads(proc.stdout)
    except ValueError:
        return 125, "", "qm guest exec printed no JSON"
    if not d.get("exited"):
        return 125, d.get("out-data", ""), "the command did not finish in " + str(timeout) + " seconds"
    return int(d.get("exitcode", 125)), d.get("out-data", ""), d.get("err-data", "")


def sh(vm: str, line: str, timeout: int = 60) -> None:
    rc, out, err = qm_exec(vm, timeout, ["/bin/sh", "-c", line])
    if rc != 0:
        sys.exit(f"guest-exec: command failed with {rc}: {err.strip() or out.strip()}")


def put(vm: str, dest: str, mode: str, src: str) -> None:
    if not re.fullmatch(r"/[A-Za-z0-9._/-]{1,120}", dest) or not re.fullmatch(r"[0-7]{3,4}", mode):
        sys.exit("guest-exec: bad destination or mode")
    data = base64.b64encode(open(src, 'rb').read()).decode()
    sh(vm, f": > {dest}.b64")
    try:
        for i in range(0, len(data), PIECE):
            sh(vm, f"printf %s {data[i:i + PIECE]} >> {dest}.b64")
        sh(vm, f"openssl base64 -d -A -in {dest}.b64 -out {dest} && chmod {mode} {dest}")
    finally:
        # The pieces are removed whichever way this ends; a failed removal is not hidden.
        sh(vm, f"rm -f {dest}.b64")


def main(argv: list[str]) -> int:
    if len(argv) >= 4 and argv[1] == "run" and argv[2].isdigit() and "--" in argv[3:4] and len(argv) > 4:
        rc, out, err = qm_exec(argv[0], int(argv[2]), argv[4:])
        sys.stdout.write(out)
        sys.stderr.write(err)
        return rc
    if len(argv) == 5 and argv[1] == "put" and argv[0].isdigit():
        put(argv[0], argv[2], argv[3], argv[4])
        return 0
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
