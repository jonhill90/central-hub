#!/usr/bin/env python3
"""List every outside source the lab's code pulls in (STD-0006).

Reads the files git tracks under hosts/ and .github/ and prints one reference per line:
  image:<registry>/<path>        a container image or OCI chart, tag and digest dropped
  url:<host>/<path>              a download, package repo or API the code fetches from,
                                 cut at the first templated part ({{ }}, $, <)
  provider:<namespace>/<name>    an OpenTofu provider
  collection:<namespace>.<name>  an Ansible collection
  pypi:<name>                    a Python package the lab installs
  action:<owner>/<repo>          a GitHub Action a workflow uses
Comment lines are skipped. Placeholders (example.com, .invalid, 127.0.0.1, localhost) are skipped.
"""
import re
import subprocess
import sys
from pathlib import Path

SKIP_DIRS = ("hosts/ansible/collections/", "node_modules/", "/tests/", ".github/foss-check/")
# Lock files of the CI checks' own Node tools: STD-0006 "Not covered yet".
SKIP_FILES = ("package-lock.json",)
CODE_EXT = (".yml", ".yaml", ".j2", ".sh", ".tf", ".py", ".example", ".json", ".cfg", ".service", ".hcl")
REGISTRIES = r"(?:docker\.io|quay\.io|ghcr\.io|registry\.k8s\.io|gcr\.io|mcr\.microsoft\.com|public\.ecr\.aws)"
IMAGE = re.compile(rf"\b{REGISTRIES}/[a-z0-9][a-z0-9._/-]*[a-z0-9]")
URL = re.compile(r"https?://[^\s\"'`)>\]]+")
PROVIDER = re.compile(r'^\s*source\s*=\s*"([a-z0-9-]+/[a-z0-9-]+)"')
USES = re.compile(r"^\s*-?\s*uses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)")
PIP = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:==|>=|~=|\[)")
PLACEHOLDER = re.compile(
    r"^(127\.|localhost|0\.0\.0\.0|json-schema\.org/"
    r"|[^/]*\b(example\.(com|org|net)|invalid|local|test|svc|svc\.cluster\.local)(:\d+)?(/|$))"
)
TEMPLATE = re.compile(r"\{|\$|<|%7B|\\")
COMMENT = re.compile(r"^\s*(#|//|--\s)")


def tracked(root: Path) -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "hosts", ".github"], check=True, capture_output=True, text=True
    ).stdout.split()
    return [p for p in out if not any(s in f"/{p}" for s in SKIP_DIRS) and Path(p).name not in SKIP_FILES]


def url_ref(raw: str) -> str | None:
    rest = raw.split("://", 1)[1]
    cut = TEMPLATE.split(rest, maxsplit=1)
    if len(cut) > 1 and "/" not in cut[0]:
        return None  # the host itself is templated: one of the lab's own names
    rest = cut[0].split("?", 1)[0].split("#", 1)[0].rstrip("/.,;:'\"")
    if not rest or PLACEHOLDER.match(rest):
        return None
    host = rest.split("/", 1)[0]
    if "." not in host or re.fullmatch(r"[\d.:]+", host):
        return None  # a bare name or an IP address is the lab's own, not an outside source
    return "url:" + rest


def scan(root: Path) -> set[str]:
    refs: set[str] = set()
    for rel in tracked(root):
        path = root / rel
        name = path.name
        if not path.is_file():
            continue
        if name == "requirements.yml" and rel.startswith("hosts/"):
            for m in re.finditer(r"^\s*-\s*name:\s*([a-z0-9_]+\.[a-z0-9_]+)", path.read_text(), re.M):
                refs.add("collection:" + m.group(1))
            continue
        if re.fullmatch(r"requirements[^/]*\.txt", name) and rel.startswith("hosts/"):
            for line in path.read_text().splitlines():
                m = PIP.match(line.strip())
                if m:
                    refs.add("pypi:" + m.group(1).lower().replace("_", "-"))
            continue
        if not name.endswith(CODE_EXT) and name not in ("Dockerfile",):
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        for line in text.splitlines():
            if COMMENT.match(line):
                continue
            code = re.split(r"\s#\s", line, maxsplit=1)[0] if not name.endswith(".py") else line
            for m in IMAGE.finditer(code):
                refs.add("image:" + m.group(0))
            for m in URL.finditer(code):
                if IMAGE.match(m.group(0).split("://", 1)[1]):
                    continue
                ref = url_ref(m.group(0))
                if ref:
                    refs.add(ref)
            if name.endswith(".tf"):
                m = PROVIDER.match(code)
                if m:
                    refs.add("provider:" + m.group(1))
            if rel.startswith(".github/workflows/"):
                m = USES.match(code)
                if m:
                    refs.add("action:" + m.group(1))
    return refs


if __name__ == "__main__":
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    for ref in sorted(scan(root)):
        print(ref)
