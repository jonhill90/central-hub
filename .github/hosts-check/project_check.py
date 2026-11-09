#!/usr/bin/env python3
"""Check that each cluster's AppProject allows everything its child Applications render.

Usage: project_check.py <repo root> <work dir>. For every hosts/kubernetes/<place>/<cluster>/root
chart that makes an AppProject, renders each app in values `apps` the way Argo CD does (an upstream
chart with its values files and zone parameters, or the local chart) and fails when an object's
namespace is not a project destination, a cluster-scoped kind is not in clusterResourceWhitelist,
or a chart repository is not in sourceRepos. Needs helm on PATH; charts are pulled as parity.py
pulls them (PARITY_CHART_CACHE).
"""
import pathlib
import sys

import yaml

from parity import ZONE, pull, run

GATEWAY = "192.0.2.10"
# Built-in cluster-scoped kinds; a CRD's own kinds are added from its spec.scope.
CLUSTER = {
    ("", "Namespace"), ("", "Node"), ("", "PersistentVolume"),
    ("rbac.authorization.k8s.io", "ClusterRole"), ("rbac.authorization.k8s.io", "ClusterRoleBinding"),
    ("apiextensions.k8s.io", "CustomResourceDefinition"),
    ("apiregistration.k8s.io", "APIService"),
    ("admissionregistration.k8s.io", "MutatingWebhookConfiguration"),
    ("admissionregistration.k8s.io", "ValidatingWebhookConfiguration"),
    ("admissionregistration.k8s.io", "ValidatingAdmissionPolicy"),
    ("admissionregistration.k8s.io", "ValidatingAdmissionPolicyBinding"),
    ("storage.k8s.io", "StorageClass"), ("storage.k8s.io", "CSIDriver"),
    ("storage.k8s.io", "VolumeAttachment"), ("scheduling.k8s.io", "PriorityClass"),
    ("networking.k8s.io", "IngressClass"), ("node.k8s.io", "RuntimeClass"),
    ("gateway.networking.k8s.io", "GatewayClass"),
}


def docs(text):
    # kube-prometheus-stack holds a bare `=` scalar, which PyYAML's safe loader reads as a value tag.
    loader = type("Loader", (yaml.SafeLoader,), {})
    loader.add_constructor("tag:yaml.org,2002:value", lambda l, n: l.construct_scalar(n))
    return [d for d in yaml.load_all(text, Loader=loader) if d]


def group(doc):
    api = doc.get("apiVersion", "")
    return api.rsplit("/", 1)[0] if "/" in api else ""


def render(top, name, app, values):
    ns, release = app["namespace"], app.get("releaseName", name)
    kube = ["--kube-version", "1.37.1"]
    zone = ["--set", f"zone={ZONE}"] if app.get("needsZone") else []
    if app.get("local"):
        return run(["helm", "template", release, str(top / "apps" / name), "-n", ns, "--set",
                    f"zone={ZONE}", "--set", f"address={GATEWAY}", "--include-crds", *kube])
    sets = list(zone)
    for path, text in (app.get("zoneParameters") or {}).items():
        sets += ["--set", f"{path}={text.replace('{zone}', ZONE).replace('{gatewayAddress}', GATEWAY)}"]
    vals = []
    for f in app.get("valueFiles") or ["values.yaml"]:
        vals += ["-f", str(top / "apps" / name / f)]
    dest = work / f"project-{top.name}-{name}"
    dest.mkdir(parents=True, exist_ok=True)
    chart = str(pull(app["chart"], dest))
    return run(["helm", "template", release, chart, "-n", ns, "--include-crds", *vals, *sets, *kube])


def check(top):
    values = yaml.safe_load((top / "root/values.yaml").read_text())
    rendered = docs(run(["helm", "template", "root", str(top / "root"), "--set", f"zone={ZONE}",
                         "--set", f"gatewayAddress={GATEWAY}"]))
    projects = [d for d in rendered if d["kind"] == "AppProject"]
    if not projects:
        return [], 0
    spec = projects[0]["spec"]
    repos = set(spec.get("sourceRepos") or [])
    places = {d["namespace"] for d in spec.get("destinations") or []}
    kinds = {(k.get("group", ""), k["kind"]) for k in spec.get("clusterResourceWhitelist") or []}
    bad, count = [], 0
    for name, app in values["apps"].items():
        source = values["repoURL"] if app.get("local") else app["chart"]["repoURL"]
        if source not in repos:
            bad.append(f"{top.name}/{name}: source {source} is not in sourceRepos")
        objs = docs(render(top, name, app, values))
        cluster = set(CLUSTER)
        for d in objs:
            if d["kind"] == "CustomResourceDefinition" and d["spec"].get("scope") == "Cluster":
                cluster.add((d["spec"]["group"], d["spec"]["names"]["kind"]))
        for d in objs:
            count += 1
            key, meta = (group(d), d["kind"]), d.get("metadata") or {}
            label = f"{top.name}/{name}: {d['kind']}/{meta.get('name')}"
            if key in cluster:
                if key not in kinds:
                    bad.append(f"{label} is cluster-scoped and not in clusterResourceWhitelist")
            elif (meta.get("namespace") or app["namespace"]) not in places:
                bad.append(f"{label} is in namespace {meta.get('namespace') or app['namespace']},"
                           " which is not a destination")
    return bad, count


if __name__ == "__main__":
    root, work = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve()
    failures, total = [], 0
    for top in sorted(p.parent.parent for p in root.glob("hosts/kubernetes/*/*/root/Chart.yaml")):
        bad, count = check(top)
        failures += bad
        total += count
    for f in failures:
        print(f, file=sys.stderr)
    print(f"project: {total} objects, {len(failures)} not allowed")
    sys.exit(1 if failures else 0)
