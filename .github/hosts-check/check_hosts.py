#!/usr/bin/env python3
"""Check the STD-0004 rules a script can see in hosts/ (STD-0005).

Usage: check_hosts.py [repo-root]   (default: the current folder)
Exit 0 when every rule holds, 1 when one fails. A known gap prints as a warning and does not
fail; each one names the rule and is removed when the code is fixed.
"""
import re
import subprocess
import sys
from pathlib import Path

# STD-0004 Terraform rule 1: the files every run folder has.
RUN_FOLDER_FILES = ["versions.tf", "providers.tf", "variables.tf", "main.tf", "outputs.tf", "backend.tf"]

# Gaps found when this check was written (2026-10-27), left for the code's owner to fix.
KNOWN_GAPS = {
    ("hosts/terraform/home/certificates", "terraform-2"): "main.tf has a locals block",
}


def tracked(root: Path, pattern: str) -> list[str]:
    out = subprocess.run(["git", "-C", str(root), "ls-files", "--", pattern],
                         check=True, capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if line]


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    failures, warnings = [], []

    def fail(where: str, rule: str, what: str) -> None:
        if (where, rule) in KNOWN_GAPS:
            warnings.append(f"{where}: STD-0004 {rule}: {what} (known gap)")
        else:
            failures.append(f"{where}: STD-0004 {rule}: {what}")

    # Terraform: every folder under hosts/terraform/<place>/ that holds .tf files is a run folder.
    for folder in sorted({p.parent for p in (root / "hosts/terraform").glob("*/*/*.tf")}):
        where = folder.relative_to(root).as_posix()
        missing = [f for f in RUN_FOLDER_FILES if not (folder / f).is_file()]
        if missing:
            fail(where, "terraform-1", "missing " + ", ".join(missing))
        for tf in sorted(folder.glob("*.tf")):
            if re.search(r"^\s*locals\s*\{", tf.read_text(), re.MULTILINE):
                fail(where, "terraform-2", f"{tf.name} has a locals block")
    for path in tracked(root, "hosts/terraform"):
        if path.endswith((".tfvars", ".tfvars.json")):
            fail(path, "terraform-5", "a real variable file is tracked; only *.tfvars.example may be")

    # Ansible roles.
    for role in sorted(p for p in (root / "hosts/ansible/roles").iterdir() if p.is_dir()):
        where = role.relative_to(root).as_posix()
        if not (role / "meta/argument_specs.yml").is_file():
            fail(where, "ansible-1", "no meta/argument_specs.yml")
        if (role / "meta/main.yml").exists():
            fail(where, "ansible-2", "has meta/main.yml")
    for path in tracked(root, "hosts/ansible/inventories"):
        if Path(path).name in ("hosts.yml", "hosts.yaml"):
            fail(path, "ansible-4", "a filled inventory is tracked; only hosts.example.yml may be")

    for w in warnings:
        print(f"warning: {w}")
    for f in failures:
        print(f"FAIL: {f}")
    if failures:
        return 1
    print("hosts code: STD-0004 checks pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
