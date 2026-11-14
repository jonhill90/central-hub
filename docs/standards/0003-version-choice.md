---
id: STD-0003
title: Version choice
status: active
scope: the version of every outside tool, package, chart or image that a runbook, code under `hosts/` or a cluster manifest installs or pins
owner-system: 8 Platform
why: the owner said yes to the proposed rule (runbooks use versions at least two weeks old, and a security fix may go in sooner) on 2026-10-25 at 04:32 UTC (message cmsg_01X43rfNYp4H1dL1V2dkfkwNCGTNvM7i1dffb9HEiVpT8m), in the project's premise review; on 2026-10-26 at 01:35 UTC to writing it down as this standard (message cmsg_01X43rfNYp4H1dL1V2dkfkwNUwoz4d5qn3nrUZSi5tveyy, answer 1); and on 2026-10-26 at 07:35 UTC (message cmsg_01X43rfNYp4H1dL1V2dkfkwNYTvYbHz6CJt5btWRHmh4nG) to covering code under `hosts/` and cluster manifests, worded as the newest release at least two weeks old
follows: []
check: none yet; a reviewing agent checks each version a runbook, `hosts/` code or a cluster manifest adds or raises, against its release date
accepted-evidence:
  approved-by: agents
  approved-at: 2026-11-14T10:58:30Z
  approved-commit: e955f9413ab135245a2e125c8cb72ee9bb1ad927
  approval-ref: the orchestrator thread's message to the audit thread of 2026-11-14 at about 10:58:30Z recording the reviewer's clearance and the passes of Councils C (10:56:26Z), A (10:56:31Z) and B (10:56:32Z) for head e955f94, each saying setting it active under D-0042 rule 3 is fine; it reached the audit thread as a thread relay, which carries no message id
  approval-names: "the pass names PR #318 and head e955f9413ab135245a2e125c8cb72ee9bb1ad927"
  check: approved-by is agents under D-0042 rule 3. The audit thread read the orchestrator's pass record at 10:58Z; it names PR #318 and the head. approved-commit is the head that holds the standard as proposed, merged as 8450530; this commit changes only status and accepted-evidence (the standard schema has no date field), plus the README index row the generator writes, which the reviewer checks (D-0001)
  merged: PR #318 merged the proposal as 8450530892283b04a2c24063eee766b6f1289243; PR #328 squash-merged this acceptance at head 3f411bdb24986e29d0c73b47c4558c3b89b04bf7 as 3fad13f13e54ecd8381ab3a828a582c2456e8624 at 2026-11-14T11:08:50Z; the follow-up PR that adds this line changes only accepted-evidence (D-0001)
---

# STD-0003: Version choice

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

## Rule

1. A version that a runbook, code under `hosts/` or a cluster manifest installs or pins MUST be the newest release that is at least two weeks old when it is pinned.
2. A release that fixes a security flaw MAY be used sooner. The runbook, code or manifest SHOULD name the fix it takes and link the advisory or release note.

Example that passes rule 1: the identity role pins Keycloak 26.8.1 (`k8s_identity_version` in `hosts/ansible/roles/k8s_identity/defaults/main.yml`). Keycloak 26.8.1 was released on 13 October 2026, and the pin reached `main` with PR #51 on 28 October 2026, fifteen days later; no newer Keycloak server release was out by 14 October. Keycloak 26.8.2, released on 5 November 2026, may replace it from 19 November 2026, two weeks after its release (source: <https://www.keycloak.org/blog>).

## Not covered here

- How a version is pinned (an exact version, a digest or a lock file), and how often pinned versions are raised.
