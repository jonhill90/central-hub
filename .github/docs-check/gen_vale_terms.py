#!/usr/bin/env python3
"""Generate the word check's Vale files from docs/glossary.md (D-0019 rule 5).

The glossary is the one source (D-0012 rule 8). The files written here are never edited by hand;
CI fails if they differ from what this script writes.

Usage: gen_vale_terms.py [repo root]   (default: current directory)
Writes: .github/vale/config/vocabularies/CentralHub/accept.txt and .github/vale/CentralHub/Terms.yml
"""
import re
import sys
from pathlib import Path

HEADER = "# Generated from docs/glossary.md by .github/docs-check/gen_vale_terms.py. Do not edit.\n"


def rows(text):
    lines = [line for line in text.splitlines() if line.startswith("|")]
    header = [c.strip().lower() for c in lines[0].strip("|").split("|")]
    for line in lines[2:]:
        cells = [c.strip() for c in line.strip("|").split("|")]
        yield dict(zip(header, cells))


def main(root):
    accept, swap = [], {}
    for r in rows((root / "docs/glossary.md").read_text()):
        if r["status"] in ("preferred", "admitted"):
            for term in (t.strip() for t in r["term"].split(",")):
                # Vale.Terms is case-aware, so a lower-case term would be flagged at the start of a
                # sentence; match lower-case terms in any case (RB-0076: "System" in docs/PRD.md).
                accept.append(f"(?i){term}" if term.islower() else term)
        for form in filter(None, (f.strip() for f in r.get("instead of", "").split(";"))):
            key = form[1:-1] if len(form) > 1 and form.startswith("/") and form.endswith("/") else re.escape(form)
            swap[key] = r["term"]
    vocab = root / ".github/vale/config/vocabularies/CentralHub"
    vocab.mkdir(parents=True, exist_ok=True)
    (vocab / "accept.txt").write_text(HEADER + "".join(f"{a}\n" for a in accept))
    style = root / ".github/vale/CentralHub"
    style.mkdir(parents=True, exist_ok=True)
    swaps = "".join(f"  '{k}': '{v}'\n" for k, v in swap.items()) if swap else "  {}\n"
    (style / "Terms.yml").write_text(
        HEADER
        + "# Report only (D-0019 check 4): a deprecated glossary word.\n"
        + "extends: substitution\n"
        + "message: \"Use '%s' instead of '%s' (docs/glossary.md).\"\n"
        + "level: warning\nignorecase: true\nswap:\n"
        + swaps
    )


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
