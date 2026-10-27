# Specs

One file per change, for work that spans several sessions or crosses systems (D-0007 rule 2). Smaller changes need only the PR description.

## How a spec moves

```text
  proposed ──(the owner: "accept PR <repo>#<n> <sha>")──▶ accepted ──(the work is finished)──▶ done
     │                                                 │
     └──────────────▶ dropped ◀────────────────────────┘        superseded: a newer spec replaces it
```

| Status | Means | Who sets it |
|---|---|---|
| `proposed` | Written on the change's branch; the PR is open | the drafting agent |
| `accepted` | The owner accepted it with a message naming the PR and its head SHA; work may start | evidence added after the owner's message, as for a decision record |
| `done` | The change it describes is finished and its acceptance criteria pass | the PR that finishes the work, which the owner accepts the same way |
| `dropped` | Stopped before it was done; the reason is in the decision log | the same way |
| `superseded` | A newer spec replaces it; `superseded-by` names it | the newer spec's PR |

After `accepted` the body is not edited (D-0007 rule 5). Only the status, the evidence and the decision log grow. A merged spec is history, not a description of how things are now.

## Steps

1. Branch per D-0002. Copy the template below to `docs/specs/YYYY-MM-<slug>.md`.
2. Fill it in. Link to code, requirement rows and decision records; never copy them (D-0007 rule 6).
3. Open the PR. The owner accepts it with `accept PR jonhill90/central-hub#<n> <sha>`.
4. Do the work. Log choices made along the way in the decision log.
5. The PR that finishes the work sets `status: done`.

## Template

```markdown
---
title: <what changes, in a few words>
status: proposed
date: YYYY-MM-DD
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# <title>

## What and why
<the change, and the problem it solves. Link the goal in docs/PRD.md it serves.>

## Out of scope
- <what this change does not do>

## Acceptance criteria
### Automated
- [ ] `<command>`: <what passing looks like>
### Manual (what the owner checks)
- [ ] <check>

## Points to (read when)
- <link>: read when <situation>

## Decision log
- YYYY-MM-DD: <choice made during the work, and why>
```

The agent that writes the code does not edit the acceptance criteria in the same step (D-0007 rule 4).

## Index

<!-- Kept by hand from each spec's front matter until the index generator covers specs. -->
| Spec | Status | Date |
|---|---|---|
| [Build the home lab from code and the first cluster c1](2026-10-home-lab-and-c1.md) | proposed | 2026-10-26 |
