---
id: STD-0001
title: Names
status: active
scope: the OS hostname of every VM, container and physical host, appliance VMs included, local or cloud, and the DNS name of every service the platform runs
owner-system: 8 Platform
why: the owner said yes to the proposed two-letter OS codes on 2026-10-21 at 01:12 UTC, and to the proposed option E (one hostname, no dashes) on 2026-10-21 at 01:13 UTC, in the project's VM naming work; to a 3 to 8 letter "what" field on 2026-10-25 at 02:58 UTC; to rule 4 (no provider, region or site in the hostname) on 2026-10-25 at 03:00 UTC; to holding service DNS names in this standard on 2026-10-25 at 03:43 UTC; to the proposed service-name pattern on 2026-10-25 at 03:54 UTC; and to its env level, numbered cluster names and short aliases on 2026-10-25 at 04:08 UTC, in the project's premise review; to covering containers and appliance VMs on 2026-10-26 at 06:04 UTC; to OS code `op` and role code `nw` on 2026-10-26 at 06:06 UTC; and to naming Proxmox resource pools by job on 2026-10-26 at 07:33 UTC
follows: [NetBIOS computer name limit (15 characters, not all digits), RFC 1123 host name label, Kubernetes node name rules, RFC 1035 CNAME records, RFC 9525 §6.3 wildcard certificates, Red Hat OpenShift cluster DNS names, kubeadm control-plane endpoint]
check: none yet in this repo; a reviewing agent checks new names and service-name patterns by hand
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-22T07:07:51Z
  approved-commit: 1c8bfdd412eade4c2470fa7959ecbd6390b25093
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNLe3Dm7Jei52vHtd4YLEnZy
  approval-names: "PR #16 and head 1c8bfdd, in the message itself"
  check: the drafting agent read the message in the Standards system thread at 2026-10-22T07:07Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #16 merged at 2026-10-22T07:09Z as 55a0276, with this evidence commit on top of the approved commit
---

# STD-0001: Names

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

## VM hostnames

A hostname MUST be five fields joined with no separator. This covers every VM, container (for example a Proxmox LXC container) and physical host, and appliance VMs such as a firewall:

`<env><os><role><what><nn>`

| Field | Length | Codes |
|---|---|---|
| env | 1 | `d` dev, `q` QA, `s` stage, `p` prod, `n` sandbox |
| os | 2 | `al` AlmaLinux, `rh` RHEL, `rk` Rocky, `ub` Ubuntu, `su` SUSE, `ar` Arch, `de` Debian, `ta` Talos, `ws` Windows Server, `wc` Windows client, `op` OPNsense |
| role | 2 | `ap` app, `db` database, `fs` file server, `dc` domain controller, `cp` Kubernetes control plane, `wk` Kubernetes worker, `hv` hypervisor, `dt` desktop, `nw` network |
| what | 3-8 | a short word for what the machine is for |
| nn | 2 | `01` to `99` |

1. A hostname MUST be 15 characters or fewer.
2. A hostname MUST use only lowercase `a-z` and `0-9`, and MUST start with a letter.
3. A hostname MUST NOT contain dashes, dots or underscores.
4. A hostname MUST NOT include the provider, the region or the site. Those belong in the platform's resource name or tags.
5. A hostname SHOULD change only when the machine is rebuilt.
6. A new code for env, os or role MUST be added to this table, with the owner's approval, before it is used.

Server and desktop are told apart by the OS code on Windows (`ws` or `wc`), and by the role on Linux (`dt` means a desktop).

Sources for the limits: NetBIOS computer names, 15 characters and not all digits (<https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou>); RFC 1123 §2.1 host name labels (<https://www.rfc-editor.org/rfc/rfc1123>); Kubernetes object names (<https://kubernetes.io/docs/concepts/overview/working-with-objects/names/>).

Example that passes: `pubapdemo01`: prod, Ubuntu, app, "demo", number 01. It is 11 characters long. The example is made up and is not a real machine.

Examples that pass for appliances and containers: `popnwdemo01` is a prod OPNsense firewall VM (OPNsense, network); `pdenwdemo01` is a prod Debian container that does a network job. Both are made up and are not real machines.

## Service names

1. A service DNS name MUST be `<component>.<cluster>.<env>.<zone>`: the most specific part first, then the cluster, the env and the zone. This follows Red Hat OpenShift's `<component>.<cluster_name>.<base_domain>`, with an env level added.
2. The env MUST always be written, prod included: `prod`, `stage`, `qa` or `dev`. Each env MAY be its own DNS zone.
3. A cluster name MUST be `c` and a number, in order: `c1`, `c2`.
4. The cluster API is `api.<cluster>.<env>.<zone>`, for example `api.c1.prod.<zone>`. Apps sit under one wildcard per cluster, `*.apps.<cluster>.<env>.<zone>`.
5. A short alias MAY point at a service name, as a DNS CNAME (RFC 1035): `<app>.<zone>` for prod, and `<app>.<env>.<zone>` for every other env. A redirect MUST NOT be used for a short alias, because it changes the name in the browser's address bar.
6. A wildcard certificate covers one label only (RFC 9525 §6.3), so each env's short aliases need their own wildcard, for example `*.dev.<zone>`. A certificate MAY list both the service name and its short alias.
7. An app that builds its own links MUST be set to the short name it is reached by, for example Grafana's root URL.

Sources: OpenShift DNS names (<https://github.com/openshift/openshift-docs/blob/main/modules/installation-dns-user-infra.adoc>); kubeadm `--control-plane-endpoint` (<https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/>); CNAME (<https://www.rfc-editor.org/rfc/rfc1035>); wildcard certificates (<https://www.rfc-editor.org/rfc/rfc9525#section-6.3>).

Example that passes: `api.c1.prod.<zone>` is cluster 1's API in prod; `grafana.<zone>` is a short alias for Grafana in prod, and `grafana.dev.<zone>` for Grafana in dev.

## Proxmox resource pools

A Proxmox resource pool is named by job, the workload it holds, for example `firewall`, `remote-access` or `k8s`.

## Not covered here

- The platform's own resource name around the hostname (for example an Azure VM resource name), and the tags. The org code and the subscription words are not settled yet.
- Real machine names and real service records. This repository is public, so the names in use live outside it.
- The value of `<zone>`. It is filled in at apply time, like machine addresses (STD-0002).
