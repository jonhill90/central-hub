---
id: STD-0003
title: Version choice
status: proposed
scope: the version of every outside tool, package, chart or image that a runbook, code under `hosts/` or a cluster manifest installs or pins
owner-system: 8 Platform
why: the owner said yes to the proposed rule (runbooks use versions at least two weeks old, and a security fix may go in sooner) on 2026-10-25 at 04:32 UTC (message cmsg_01X43rfNYp4H1dL1V2dkfkwNCGTNvM7i1dffb9HEiVpT8m), in the project's premise review; on 2026-10-26 at 01:35 UTC to writing it down as this standard (message cmsg_01X43rfNYp4H1dL1V2dkfkwNUwoz4d5qn3nrUZSi5tveyy, answer 1); and on 2026-10-26 at 07:35 UTC (message cmsg_01X43rfNYp4H1dL1V2dkfkwNYTvYbHz6CJt5btWRHmh4nG) to covering code under `hosts/` and cluster manifests, worded as the newest release at least two weeks old
follows: []
check: none yet; a reviewing agent checks each version a runbook, `hosts/` code or a cluster manifest adds or raises, against its release date
---

# STD-0003: Version choice

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

## Rule

1. A version that a runbook, code under `hosts/` or a cluster manifest installs or pins MUST be the newest release that is at least two weeks old when it is pinned.
2. A release that fixes a security flaw MAY be used sooner. The runbook, code or manifest SHOULD name the fix it takes and link the advisory or release note.

Example that passes rule 1: the identity role pins Keycloak 26.8.1 (`k8s_identity_version` in `hosts/ansible/roles/k8s_identity/defaults/main.yml`). Keycloak 26.8.1 was released on 13 October 2026, and the pin reached `main` with PR #51 on 28 October 2026, fifteen days later; no newer Keycloak server release was out by 14 October. Keycloak 26.8.2, released on 5 November 2026, may replace it from 19 November 2026, two weeks after its release (source: <https://www.keycloak.org/blog>).

## Not covered here

- How a version is pinned (an exact version, a digest or a lock file), and how often pinned versions are raised.
