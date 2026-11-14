#!/usr/bin/env python3
"""The FOSS check (STD-0006): every outside source has a complete register row, and every row
that fails the test has a named exception.

  python3 -I .github/foss-check/check_components.py [repo root]

Exit 0 when clean (pending exceptions are reported, not failed), 1 on any error.
"""
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scan import scan  # noqa: E402

REGISTER = "docs/standards/components.yaml"
EXCEPTIONS = "docs/standards/foss-exceptions.yaml"
NEEDED = ("name", "kind", "used-for", "licence", "licence-source", "paid-edition", "paid-edition-source", "verdict", "sources", "checked")
URL = re.compile(r"^https://[^\s/]+\.[^\s/]+(/\S*)?$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def text(value) -> str:
    return value.strip() if isinstance(value, str) else ""


def check(root: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    notes: list[str] = []
    rows = (yaml.safe_load((root / REGISTER).read_text()) or {}).get("components") or []
    excs = (yaml.safe_load((root / EXCEPTIONS).read_text()) or {}).get("exceptions") or []

    names: dict[str, dict] = {}
    for i, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            errors.append(f"{REGISTER}: row {i} is not a mapping")
            continue
        name = text(row.get("name")) or f"row {i}"
        where = f"{REGISTER}: {name}"
        if name in names:
            errors.append(f"{where}: name used twice")
        names[name] = row
        for field in NEEDED:
            if field == "sources":
                if not isinstance(row.get("sources"), list):
                    errors.append(f"{where}: sources must be a list")
            elif field == "checked":
                if not DATE.match(str(row.get("checked", ""))):
                    errors.append(f"{where}: checked must be a date, YYYY-MM-DD")
            elif not text(row.get(field)):
                errors.append(f"{where}: {field} is missing")
        for field in ("licence-source", "paid-edition-source"):
            if text(row.get(field)) and not URL.match(text(row.get(field))):
                errors.append(f"{where}: {field} must be an https address of the page opened")
        if re.search(r"\bnot checked\b|\bunknown\b|\bTBD\b", " ".join(text(row.get(f)) for f in NEEDED if f != "sources"), re.I):
            errors.append(f"{where}: a field says not checked; open the page and fill it in")
        kind, verdict = text(row.get("kind")), text(row.get("verdict"))
        if kind not in ("software", "hosted"):
            errors.append(f"{where}: kind must be software or hosted")
        if verdict not in ("pass", "fail", "hosted"):
            errors.append(f"{where}: verdict must be pass, fail or hosted")
        if (verdict == "hosted") != (kind == "hosted"):
            errors.append(f"{where}: verdict hosted goes with kind hosted, and only with it")
        if verdict in ("hosted", "fail") and not text(row.get("exit-path")):
            errors.append(f"{where}: exit-path is missing (STD-0006 rule 3)")
        if isinstance(row.get("sources"), list) and not row["sources"] and not text(row.get("not-detected")):
            errors.append(f"{where}: no sources, so not-detected must say how it is installed")

    excepted: dict[str, dict] = {}
    for i, exc in enumerate(excs, 1):
        comp = text((exc or {}).get("component"))
        where = f"{EXCEPTIONS}: {comp or f'entry {i}'}"
        if comp not in names:
            errors.append(f"{where}: no register row has this name")
            continue
        if comp in excepted:
            errors.append(f"{where}: listed twice")
        excepted[comp] = exc
        state = text(exc.get("state"))
        if state == "kept":
            if not re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}(:\d{2})? UTC", text(exc.get("decided"))):
                errors.append(f"{where}: kept needs decided with the owner's message time in UTC")
        elif state == "pending":
            if not text(exc.get("listed")):
                errors.append(f"{where}: pending needs listed")
        else:
            errors.append(f"{where}: state must be kept or pending")
        if text(names[comp].get("verdict")) != "fail":
            errors.append(f"{where}: its row passes, so the exception is not needed; remove it")

    for name, row in names.items():
        if text(row.get("verdict")) == "fail":
            exc = excepted.get(name)
            if not exc:
                errors.append(f"{REGISTER}: {name} fails STD-0006 and has no named exception")
            elif text(exc.get("state")) == "pending":
                notes.append(f"pending: {name} fails STD-0006 and waits for the owner's call")
            else:
                notes.append(f"kept: {name} ({text(exc.get('decided'))[:60]}...)")

    prefixes = [(p, name) for name, row in names.items() for p in (row.get("sources") or []) if isinstance(p, str)]
    used: set[str] = set()
    for ref in sorted(scan(root)):
        hits = {name for p, name in prefixes if ref.startswith(p)}
        if not hits:
            errors.append(f"{ref}: no register row in {REGISTER} has a source this starts with")
        used |= {p for p, _ in prefixes if ref.startswith(p)}
    for p, name in prefixes:
        if p not in used:
            notes.append(f"unused: {name} source {p} matches nothing the scanner found")
    return errors, notes


if __name__ == "__main__":
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    errors, notes = check(root)
    for n in notes:
        print(f"note: {n}")
    for e in errors:
        print(f"error: {e}")
    print(f"{len(errors)} errors")
    sys.exit(1 if errors else 0)
