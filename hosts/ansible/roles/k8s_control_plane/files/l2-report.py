#!/usr/bin/env python3
"""Which node announces each load-balancer address (D-0062). Read-only.

One line per LoadBalancer Service: its address, the L2 announcement policy meant to announce it (its own, named by the
label central-hub/l2-policy, or the general one), and the node holding its lease cilium-l2announce-<namespace>-<name>
in kube-system (Cilium v1.20.4 docs, network/l2-announcements.rst lines 240-259). With the policies, one line per
CiliumL2AnnouncementPolicy and its service selector. PASS when every Service with an address has a lease holder; FAIL,
exit 1, on one with none, on no LoadBalancer Service at all, or on a failed read.

  l2-report.py <services.json> <leases.json>   from files (hosts/rebuild-k8s.sh, dev's gateway stage)
  l2-report.py --kubectl                       reads them with kubectl as root on a control-plane node, with the
                                               policies too (role k8s_control_plane, tag lb: openbao-prod l2-policy)
"""
import json
import subprocess
import sys


def kubectl(*args):
    return json.loads(subprocess.run(["kubectl", *args, "-o", "json"], check=True, capture_output=True, text=True,
                                     timeout=60).stdout)


def main(argv):
    policies = None
    try:
        if argv == ["--kubectl"]:
            svcs = kubectl("get", "svc", "-A")
            leases = kubectl("-n", "kube-system", "get", "leases")
            policies = kubectl("get", "ciliuml2announcementpolicies.cilium.io")
        elif len(argv) == 2:
            svcs, leases = (json.load(open(p)) for p in argv)
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError, subprocess.SubprocessError):
        print("l2: FAIL: the Services, leases or policies could not be read")
        return 1
    holders = {l["metadata"]["name"]: (l.get("spec") or {}).get("holderIdentity") or "" for l in leases["items"]}
    for p in sorted((policies or {}).get("items", []), key=lambda p: p["metadata"]["name"]):
        sel = (p.get("spec") or {}).get("serviceSelector") or {}
        print("l2: policy %s serviceSelector %s" % (p["metadata"]["name"], json.dumps(sel, sort_keys=True)))
    n = bad = 0
    for s in sorted(svcs["items"], key=lambda s: (s["metadata"]["namespace"], s["metadata"]["name"])):
        if (s.get("spec") or {}).get("type") != "LoadBalancer":
            continue
        n += 1
        ns, name = s["metadata"]["namespace"], s["metadata"]["name"]
        policy = (s["metadata"].get("labels") or {}).get("central-hub/l2-policy") or "general"
        ingress = ((s.get("status") or {}).get("loadBalancer") or {}).get("ingress") or []
        ips = [i["ip"] for i in ingress if i.get("ip")]
        holder = holders.get("cilium-l2announce-%s-%s" % (ns, name), "")
        print("l2: service %s/%s address %s policy %s lease %s" % (ns, name, ",".join(ips) or "none", policy,
                                                                   holder or "none"))
        if ips and not holder:
            bad += 1
    print("l2: %d LoadBalancer Services, %d with an address and no lease holder" % (n, bad))
    if n == 0 or bad:
        print("l2: FAIL: %s" % ("no LoadBalancer Service" if n == 0 else "an address no node announces"))
        return 1
    print("l2: PASS: every LoadBalancer Service with an address has a lease holder")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
