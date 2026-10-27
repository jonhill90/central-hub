---
id: STD-0003
title: Version choice
status: proposed
scope: the version of every outside tool, package, chart or image that a runbook, code under `hosts/` or a cluster manifest installs or pins
owner-system: 8 Platform
why: the owner said yes to the proposed rule (runbooks use versions at least two weeks old, and a security fix may go in sooner) on 2026-10-25 at 04:32 UTC, in the project's premise review, and on 2026-10-26 at 01:35 UTC to writing it down as this standard, and on 2026-10-26 at 07:35 UTC to covering code under `hosts/` and cluster manifests, worded as the newest release at least two weeks old
follows: []
check: none yet; a reviewing agent checks each version a runbook, `hosts/` code or a cluster manifest adds or raises, against its release date
---

# STD-0003: Version choice

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

## Rule

1. A version that a runbook, code under `hosts/` or a cluster manifest installs or pins MUST be the newest release that is at least two weeks old when it is pinned.
2. A release that fixes a security flaw MAY be used sooner. The runbook, code or manifest SHOULD name the fix it takes and link the advisory or release note.

Example that passes: `build-kubeadm-cluster.md` step 26 pins Traefik chart 42.1.3, published 2026-10-22, less than two weeks before the runbook was updated. The runbook names the 12 security advisories that v3.7.14 to v3.7.16 fix and links the release notes, so rule 2 applies.

## Not covered here

- How a version is pinned (an exact version, a digest or a lock file), and how often pinned versions are raised.
