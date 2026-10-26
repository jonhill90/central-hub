#!/usr/bin/env python3
"""Check that the home VLAN list in code matches STD-0002.

STD-0002's "Home VLANs" table is the rule. hosts/ansible/inventories/home/group_vars/all/vlans.yml
(list `lab_vlans`) is its copy in code, which Terraform and Ansible both read. This check fails when
they differ in a VLAN ID, its use (the file's `alias`) or its prefix.

Usage: check_vlans.py [repo root]   (default: current directory)
Exit 1 when they differ. Needs: ruamel.yaml, pinned in requirements.txt.
"""
import re
import sys
from pathlib import Path

from ruamel.yaml import YAML
from ruamel.yaml.error import YAMLError

STD = "docs/standards/0002-ip-address-plan.md"
CODE = "hosts/ansible/inventories/home/group_vars/all/vlans.yml"


def from_standard(text):
    """VLAN ID -> (use, prefix) from the table under the "### Home VLANs" heading."""
    part = re.search(r"^### Home VLANs\n(.*?)(?=^#)", text, re.S | re.M)
    if not part:
        raise ValueError(f"{STD}: no '### Home VLANs' section")
    rows = {}
    for line in part.group(1).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.startswith("|") else []
        if len(cells) < 3 or not cells[0].isdigit():
            continue  # not a row, the header or the separator
        rows[int(cells[0])] = (cells[2].lower(), cells[1].strip("`"))
    if not rows:
        raise ValueError(f"{STD}: the Home VLANs table has no rows")
    return rows


def from_code(text):
    """VLAN ID -> (use, prefix) from the `lab_vlans` list."""
    data = YAML(typ="safe", pure=True).load(text)
    vlans = (data or {}).get("lab_vlans")
    if not isinstance(vlans, list) or not vlans:
        raise ValueError(f"{CODE}: no `lab_vlans` list")
    rows = {}
    for v in vlans:
        rows[int(v["id"])] = (str(v["alias"]).lower(), str(v["cidr"]))
    return rows


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    try:
        std = from_standard((root / STD).read_text())
        code = from_code((root / CODE).read_text())
    except (OSError, ValueError, KeyError, TypeError, YAMLError) as e:
        print(f"vlans: {e}", file=sys.stderr)
        return 1
    errors = []
    for vid in sorted(set(std) | set(code)):
        if vid not in code:
            errors.append(f"VLAN {vid} is in {STD} but not in {CODE}")
        elif vid not in std:
            errors.append(f"VLAN {vid} is in {CODE} but not in {STD}")
        else:
            for what, s, c in (("use", std[vid][0], code[vid][0]), ("prefix", std[vid][1], code[vid][1])):
                if s != c:
                    errors.append(f"VLAN {vid} {what}: {STD} says '{s}', {CODE} says '{c}'")
    for e in errors:
        print(f"vlans: {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"vlans: {len(std)} home VLANs match STD-0002")
    return 0


if __name__ == "__main__":
    sys.exit(main())
