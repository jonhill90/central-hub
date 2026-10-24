#!/usr/bin/env python3
"""Generate the index tables in docs/decisions/README.md and docs/standards/README.md.

D-0001 "Index": the decisions index is generated from each record's front matter and never edited
by hand. The standards register table is generated the same way. Only the table that starts with
"| ID |" is rewritten; the prose above it stays as written.

Usage: gen_index.py [--check] [repo root]   (default: current directory)
With --check, nothing is written, and the exit code is 1 if a README differs from what would be written.
Reads only one-line top-level front matter fields, so it needs no packages beyond the standard library.
"""
import re
import sys
from pathlib import Path

FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.S)

# folder, file pattern, table header, row builder
TABLES = [
    (
        "docs/decisions",
        re.compile(r"^\d{4}-[a-z0-9-]+\.md$"),
        "| ID | Title | Status | Waits on | Date |",
        lambda fm, name: [fm["id"], f"[{fm['title']}]({name})", fm["status"],
                          ", ".join(fm.get("waits-on") or []) or "—", fm["date"]],
    ),
    (
        "docs/standards",
        re.compile(r"^\d{4}-[a-z0-9-]+\.md$"),
        "| ID | Title | Status | Scope | Owner system |",
        lambda fm, name: [fm["id"], f"[{fm['title']}]({name})", fm["status"],
                          fm.get("scope", ""), fm.get("owner-system", "")],
    ),
]


def value(raw):
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        return [v.strip() for v in raw[1:-1].split(",") if v.strip()]
    if len(raw) > 1 and raw[0] == raw[-1] and raw[0] in "\"'":
        return raw[1:-1]
    return raw


def front_matter(path):
    m = FRONT.match(path.read_text())
    if not m:
        raise SystemExit(f"{path}: no front matter")
    fields = {}
    for line in m.group(1).splitlines():
        key, sep, rest = line.partition(":")
        if sep and key and not key.startswith((" ", "#")):
            fields[key] = value(rest)
    return fields


def table(folder, pattern, header, row):
    lines = [header, "|" + "---|" * header.count(" | ") + "---|"]
    for path in sorted(folder.iterdir()):
        if pattern.match(path.name):
            lines.append("| " + " | ".join(row(front_matter(path), path.name)) + " |")
    return lines


def render(readme, lines):
    old = readme.read_text().splitlines()
    start = next((i for i, line in enumerate(old) if line.startswith("| ID |")), None)
    if start is None:
        raise SystemExit(f"{readme}: no table starting with '| ID |'")
    end = start
    while end < len(old) and old[end].startswith("|"):
        end += 1
    return "\n".join(old[:start] + lines + old[end:]) + "\n"


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    root = Path(args[0] if args else ".")
    stale = []
    for folder, pattern, header, row in TABLES:
        readme = root / folder / "README.md"
        new = render(readme, table(root / folder, pattern, header, row))
        if readme.read_text() != new:
            stale.append(readme.relative_to(root).as_posix())
            if not check:
                readme.write_text(new)
    if check and stale:
        for s in stale:
            print(f"error: {s} differs from the front matter; run .github/docs-check/gen_index.py and commit the result")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
