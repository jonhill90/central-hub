#!/usr/bin/env python3
"""Check central-hub front matter and the cross-file rules the records state.

D-0019 check 1. Run it with run.sh, which CI runs too.

Usage: check_docs.py [repo root]   (default: current directory)
Exit 1 when any error is found. Warnings never fail.
Needs: ruamel.yaml (YAML 1.2, fails on duplicate keys) and jsonschema, pinned in requirements.txt.
"""
import json
import re
import sys
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from ruamel.yaml import YAML
from ruamel.yaml.constructor import SafeConstructor
from ruamel.yaml.error import YAMLError

HERE = Path(__file__).resolve().parent
FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.S)

# Which schema each file gets. Files outside these patterns are not checked here.
KINDS = [
    ("decision", re.compile(r"^docs/decisions/(\d{4})-[a-z0-9-]+\.md$")),
    ("evidence", re.compile(r"^docs/research/(\d{4})-[a-z0-9-]+\.md$")),
    ("standard", re.compile(r"^docs/standards/(\d{4})-[a-z0-9-]+\.md$")),
    ("spec", re.compile(r"^docs/specs/(\d{4}-\d{2})-[a-z0-9-]+\.md$")),
    ("runbook", re.compile(r"^docs/runbooks/(?!README)[a-z0-9-]+\.md$")),
    ("postmortem", re.compile(r"^docs/postmortems/(\d{4}-\d{2}-\d{2})-[a-z0-9-]+\.md$")),
]


class StringDates(SafeConstructor):
    """Keep dates and times as the strings written, so JSON Schema sees what was written."""


StringDates.add_constructor("tag:yaml.org,2002:timestamp", SafeConstructor.construct_yaml_str)


def yaml_12():
    # YAML 1.2: `yes`, `no`, `on` and `off` stay strings; a repeated key is an error, not a silent overwrite.
    y = YAML(typ="safe", pure=True)
    y.Constructor = StringDates
    y.allow_duplicate_keys = False
    return y


def load_validators():
    schemas = {p.name: json.loads(p.read_text()) for p in (HERE / "schemas").glob("*.schema.json")}
    registry = Registry().with_resources(
        (name, Resource.from_contents(s)) for name, s in schemas.items()
    )
    return {
        kind: Draft202012Validator(schemas[f"{kind}.schema.json"], registry=registry)
        for kind, _ in KINDS
    }


def main(root: Path) -> int:
    errors, warnings = [], []
    validators = load_validators()
    loader = yaml_12()
    docs = {}  # path -> (kind, number, front matter, body)
    unreadable = set()  # paths and IDs whose front matter did not parse; links to them are not checked

    for path in sorted(root.glob("docs/**/*.md")):
        rel = path.relative_to(root).as_posix()
        kind = number = None
        for k, pattern in KINDS:
            m = pattern.match(rel)
            if m:
                kind, number = k, (m.group(1) if m.groups() else None)
        if not kind:
            continue
        text = path.read_text()
        m = FRONT.match(text)
        if not m:
            errors.append(f"{rel}: no front matter")
            continue
        try:
            fm = loader.load(m.group(1))
        except YAMLError as e:
            mark = getattr(e, "problem_mark", None)
            where = f" (front matter line {mark.line + 1})" if mark else ""
            problem = getattr(e, "problem", None) or str(e).splitlines()[0]
            errors.append(f"{rel}: front matter is not valid YAML{where}: {problem}")
            unreadable.update({rel, f"D-{number}"} if kind == "decision" else {rel})
            continue
        for err in sorted(validators[kind].iter_errors(fm), key=lambda e: list(e.path)):
            field = "/".join(str(p) for p in err.path) or "(top)"
            errors.append(f"{rel}: {field}: {err.message}")
        docs[rel] = (kind, number, fm or {}, text[m.end():])

    decisions = {fm.get("id"): (rel, fm, body) for rel, (k, n, fm, body) in docs.items() if k == "decision"}

    for rel, (kind, number, fm, body) in docs.items():
        # ID matches the file name number (D-0001; standards README).
        if kind == "decision" and fm.get("id") != f"D-{number}":
            errors.append(f"{rel}: id {fm.get('id')} does not match file name D-{number}")
        if kind == "standard" and fm.get("id") != f"STD-{number}":
            errors.append(f"{rel}: id {fm.get('id')} does not match file name STD-{number}")
        if isinstance(fm.get("accepted-evidence"), dict) and "quote" in fm["accepted-evidence"]:
            warnings.append(f"{rel}: accepted-evidence still has the D-0001 quote shape (D-0016 rule 6 cleanup)")

        if kind == "evidence":
            # D-0017 rules 1 and 4: same file name as its record, front matter names it, record links it.
            twin = rel.replace("docs/research/", "docs/decisions/")
            if twin in unreadable:
                pass
            elif twin not in docs:
                errors.append(f"{rel}: no record with the same file name in docs/decisions/")
            elif docs[twin][2].get("id") != fm.get("record"):
                errors.append(f"{rel}: record {fm.get('record')} is not the id of {twin}")
            elif f"../research/{Path(rel).name}" not in docs[twin][3]:
                errors.append(f"{twin}: does not link its evidence file ../research/{Path(rel).name}")

        if kind == "decision":
            did = fm.get("id")
            for ref in fm.get("waits-on") or []:
                if ref.startswith("D-") and ref not in decisions and ref not in unreadable:
                    errors.append(f"{rel}: waits-on {ref} has no record")
            # Symmetric links (D-0001 supersedes; D-0016 Confirmation amends).
            for fwd, back in (("supersedes", "superseded-by"), ("amends", "amended-by")):
                for ref in fm.get(fwd) or []:
                    other = decisions.get(ref)
                    if ref in unreadable:
                        continue
                    if not other:
                        errors.append(f"{rel}: {fwd} {ref} has no record")
                        continue
                    theirs = other[1].get(back)
                    theirs = theirs if isinstance(theirs, list) else [theirs]
                    if did not in theirs:
                        errors.append(f"{other[0]}: {back} should include {did} ({rel} says {fwd} {ref})")
            for back, fwd in (("superseded-by", "supersedes"), ("amended-by", "amends")):
                refs = fm.get(back)
                for ref in (refs if isinstance(refs, list) else [refs] if refs else []):
                    other = decisions.get(ref)
                    if ref in unreadable:
                        continue
                    if not other or did not in (other[1].get(fwd) or []):
                        errors.append(f"{rel}: {back} {ref}, but that record does not list {did} in {fwd}")

    # waits-on has no cycles (D-0001).
    graph = {d: [r for r in (v[1].get("waits-on") or []) if r in decisions] for d, v in decisions.items()}
    state = {}

    def visit(node, trail):
        state[node] = 1
        for nxt in graph.get(node, []):
            if state.get(nxt) == 1:
                errors.append(f"waits-on cycle: {' -> '.join(trail + [node, nxt])}")
            elif not state.get(nxt):
                visit(nxt, trail + [node])
        state[node] = 2

    for d in graph:
        if not state.get(d):
            visit(d, [])

    # docs/decisions/ has no subfolders (D-0017 Confirmation).
    for sub in (root / "docs/decisions").iterdir():
        if sub.is_dir():
            errors.append(f"docs/decisions/{sub.name}/: subfolder not allowed (D-0017)")

    # Each kind folder README lists every file in it (D-0012 rule 4, D-0017 rule 3).
    for folder in ("decisions", "research", "standards"):
        readme = root / f"docs/{folder}/README.md"
        if not readme.exists():
            continue
        index = readme.read_text()
        for rel in docs:
            if rel.startswith(f"docs/{folder}/") and f"({Path(rel).name})" not in index:
                errors.append(f"docs/{folder}/README.md: does not list {Path(rel).name}")

    # The decision index rows match the records (D-0001 "Index").
    index = (root / "docs/decisions/README.md").read_text() if (root / "docs/decisions/README.md").exists() else ""
    for did, (rel, fm, _) in decisions.items():
        row = re.search(rf"^\| {re.escape(str(did))} \|[^\n]*\| (\w+) \|", index, re.M)
        if row and row.group(1) != fm.get("status"):
            errors.append(f"docs/decisions/README.md: {did} status is {row.group(1)}, record says {fm.get('status')}")

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    print(f"{len(docs)} files checked, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
