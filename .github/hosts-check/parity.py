#!/usr/bin/env python3
"""Check that Argo CD's files render the same objects the Ansible roles apply today.

Usage: parity.py <repo root> <work dir>. Reads .github/hosts-check/manifests/parity.txt; needs
helm and ansible-playbook on PATH. Exits 1 on any difference, printing each one.
"""
import os
import pathlib
import shlex
import subprocess
import sys
import time

import yaml

ZONE = "example.com"


def run(args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout


def pull(chart, dest):
    """Download an upstream chart once: from PARITY_CHART_CACHE when it holds this name and version
    (CI keeps that folder with actions/cache), else from its repository, with retries and backoff,
    so a short outage upstream doesn't fail the check."""
    cache = os.environ.get("PARITY_CHART_CACHE")
    folder = pathlib.Path(cache) / f"{chart['name']}-{chart['version']}" if cache else dest
    # A chart with an `oci` copy (root values) is pulled from there: the same file, without the
    # repository index and GitHub release download that an outage can take away.
    if chart.get("oci"):
        args = ["helm", "pull", chart["oci"], "--version", str(chart["version"])]
    else:
        args = ["helm", "pull", chart["name"], "--repo", chart["repoURL"], "--version",
                str(chart["version"])]
    if not (folder / chart["name"] / "Chart.yaml").exists():
        for attempt in range(5):
            try:
                run([*args, "--untar", "--untardir", str(folder)])
                break
            except subprocess.CalledProcessError as err:
                if attempt == 4:
                    sys.stderr.write(err.stderr)
                    raise
                wait = 2 ** (attempt + 1)
                print(f"helm pull {chart['name']} {chart['version']} failed, retrying in {wait}s",
                      file=sys.stderr)
                time.sleep(wait)
    return folder / chart["name"]


def objects(text):
    out = {}
    for doc in yaml.safe_load_all(text):
        if not doc:
            continue
        meta = doc.setdefault("metadata", {})
        notes = {k: v for k, v in (meta.get("annotations") or {}).items()
                 if not k.startswith(("argocd.argoproj.io/", "helm.sh/"))}
        if notes:
            meta["annotations"] = notes
        else:
            meta.pop("annotations", None)
        out[(doc["kind"], meta.get("name"))] = doc
    return out


def drop(doc, dotted):
    """Remove one field; a key that holds a slash or a dot is matched whole from the end."""
    node, parts = doc, dotted.split(".")
    while parts:
        if not isinstance(node, dict):
            return
        rest = ".".join(parts)
        if rest in node:
            node.pop(rest)
            return
        node = node.get(parts.pop(0))


def compare(case, left, right, subset, ignores):
    bad = []
    for key, want in left.items():
        got = right.get(key)
        if got is None:
            bad.append(f"{case}: {key[0]}/{key[1]} is missing from the Argo CD side")
            continue
        for kind_name, path in ignores:
            if kind_name == f"{key[0]}/{key[1]}":
                drop(want, path)
                drop(got, path)
        if want != got:
            a = yaml.safe_dump(want, sort_keys=True).splitlines()
            b = yaml.safe_dump(got, sort_keys=True).splitlines()
            import difflib
            diff = "\n".join(difflib.unified_diff(a, b, "ansible", "argocd", lineterm="", n=2))
            bad.append(f"{case}: {key[0]}/{key[1]} differs\n{diff}")
    if not subset:
        for key in right.keys() - left.keys():
            bad.append(f"{case}: {key[0]}/{key[1]} is only on the Argo CD side")
    return bad


def main():
    root, work = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve()
    here = root / ".github/hosts-check/manifests"
    ansible = root / "hosts/ansible"
    failures, count = [], 0
    for n, line in enumerate((here / "parity.txt").read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        words = shlex.split(line, posix=False)
        mode, cluster, app, role, source = words[:5]
        settings, files, params, ignores = "{}", ["values.yaml"], [], []
        for word in words[5:]:
            if word.startswith("{"):
                settings = word
            elif word.startswith("files="):
                files = word[6:].split(",")
            elif word.startswith("param="):
                path, _, text = word[6:].partition("=")
                params.append(f"{path}={text.replace('{zone}', ZONE)}")
            elif word.startswith("set="):
                params.append(word[4:])
            elif word.startswith("ignore="):
                kind_name, _, path = word[7:].partition(":")
                ignores.append((kind_name, path))
        # hosts/kubernetes/<place>/<cluster>/ (D-0011 rule 1); a cluster name is unique across places.
        top = next((root / "hosts/kubernetes").glob(f"*/{cluster}"))
        entry = yaml.safe_load((top / "root/values.yaml").read_text())["apps"][app]
        ns, release = entry["namespace"], entry.get("releaseName", app)
        case = f"parity.txt:{n} {mode} {app}"
        dest = work / f"parity-{n}"
        dest.mkdir(parents=True, exist_ok=True)
        kube = ["--kube-version", "1.37.1"]
        if mode == "manifest":
            out = dest / "ansible.yaml"
            run(["ansible-playbook", "-i", "localhost,", str(here / "render.yml"), "-e", f"role={role}",
                 "-e", f"template={source}", "-e", f"dest={out}", "-e", settings], cwd=ansible)
            left = objects(out.read_text())
            sets = [x for p in params for x in ("--set", p)]
            right = objects(run(["helm", "template", release, str(top / "apps" / app), "-n", ns,
                                 "--set", f"zone={ZONE}", *sets, *kube]))
            failures += compare(case, left, right, True, ignores)
        elif mode == "values":
            out = dest / "values.json"
            run(["ansible-playbook", "-i", "localhost,", str(here / "values-dump.yml"), "-e", f"role={role}",
                 "-e", f"var={source}", "-e", f"dest={out}", "-e", settings], cwd=ansible)
            path = str(pull(entry["chart"], dest / "chart"))
            left = objects(run(["helm", "template", release, path, "-n", ns, "-f", str(out), *kube]))
            sets = []
            for p, text in (entry.get("zoneParameters") or {}).items():
                sets += ["--set", f"{p}={text.replace('{zone}', ZONE)}"]
            for p in params:
                sets += ["--set", p]
            vals = []
            for f in files:
                vals += ["-f", str(top / "apps" / app / f)]
            right = objects(run(["helm", "template", release, path, "-n", ns, *vals, *sets, *kube]))
            failures += compare(case, left, right, False, ignores)
        else:
            failures.append(f"parity.txt:{n}: unknown mode {mode}")
            continue
        count += 1
    for f in failures:
        print(f, file=sys.stderr)
    print(f"parity: {count} cases, {len(failures)} differences")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
