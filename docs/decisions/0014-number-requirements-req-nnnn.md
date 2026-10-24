---
id: D-0014
title: Number requirements REQ-NNNN
status: accepted
date: 2026-10-23
decision-makers: [owner]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0003, D-0004, D-0006]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-23T03:46:26Z
  approved-commit: f62845acd38deb7018acd8f96a2a484677976c8c
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwN12EqNFjmi5fTVUJmrD9vhd
  approval-names: "PR #22 and head f62845a, in the message itself"
  check: the drafting agent read the message in the "Requirements register and SR ids" thread at 2026-10-23T03:46Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #22 merged at 2026-10-23T03:50Z as 05a48ff, with this evidence commit on top of the approved commit
revisit-when: the Activation gate passes (D-0003 rule 5 then stops ID changes); a search finds a requirement cited in another form; or a requirements tool is adopted that brings its own ID scheme
---

# Number requirements REQ-NNNN

## Context and Problem Statement

Requirements are kept in one register in the Research repo, and they are cited from this repo, from chats and from each other. On 2026-10-23 the owner said the requirement ID format had been made up by agents and had never had the scrutiny other choices got. The check that followed (research batch RB-0072, [evidence](../research/0014-number-requirements-req-nnnn.md)) found:

- An agent coordinator wrote the format on 2026-10-06, before this project existed. The owner said yes to each requirement's wording, never to the format.
- The format had no dash and two digits, unlike the house style the other families use (`D-0007`, `STD-0001`: a prefix, a dash and four digits).
- Its two-letter prefix clashed outside the project: NIST SP 800-53 uses the same letters for its Supply Chain Risk Management controls (`SR-3`). Under D-0003 rule 2, it would also block any future prefix that starts with those letters.

The owner chose `REQ-0000` style on 2026-10-23 at 03:38 UTC. The owner preferred it, and said that a format already in use is not a good reason to keep it in a system that is still almost greenfield: IDs are only words, they should be fixed where possible, and the same goes for the other IDs.

## Decision Drivers

- **Match what exists:** `D-0007` and `STD-0001` use a dash and four digits.
- **One name per thing:** two live names for one requirement is the confusion RB-0003 measured (`P1` had 7 meanings).
- **Greenfield:** Foundation is the cheapest time to fix an ID, because the number of citations grows every day.
- **Records stay true:** chat archives and git history are records of what was said and must not change.
- **Replaceable** (REQ-0011).

## Considered Options

1. **`REQ-NNNN`, written the same way in every live file during Foundation.**
2. **`REQ-NNNN` for new citations only,** with each row also keeping the ID it had (D-0003 rule 5 with no Foundation part).
3. **Keep the agent-made format** and only write it down (the agent's first draft v0.1).

## Decision Outcome

Chosen option: **1**, which the owner chose on 2026-10-23 at 03:38 UTC.

This sets the Requirements row of D-0003's registry to `REQ-NNNN`. It also adds D-0003 rule 5: until the Activation gate passes, the owner may approve changing an agent-made ID or label in every live file, and each change is one line in a corrections log. `REQ-` passes D-0003 rule 2's prefix check against `D-` and `STD-`.

### The requirements register

- Every requirement has one ID, `REQ-NNNN`, with four digits. Its number is assigned only after the owner says yes to the wording, and it is the next free number.
- A void requirement keeps a tombstone line in the register (D-0004 rule 5).
- The register check (`check_register.py` in the Research repo, with its tests) fails on a requirement ID that is not in `REQ-NNNN` form, in the register or in the project instructions.
- Project instructions that cite a requirement are drafted by the agent, approved by the owner and saved by the coordinator.

### Consequences

- Good: requirements look like the other families, and the prefix does not clash with NIST's families or block future prefixes.
- Good: each requirement has one name.
- Bad: during Foundation, a changed ID has to be written in every live file in three places, with the owner's approval each time.
- Neutral: a requirement's wording and meaning do not depend on its number.

### Confirmation

- A search of every live file finds requirement IDs only in `REQ-NNNN` form.
- The register check fails on a requirement ID in any other form, in the register or in the project instructions.
- The D-0003 review checks still apply: bare one-letter labels, non-unique global IDs, and prefixes missing from the registry.

## Pros and Cons of the Options

### 1. REQ-NNNN in every live file

- Good: one name per requirement, and house style.
- Bad: the largest one-time effort.

### 2. REQ-NNNN for new citations only

- Good: no existing file changes.
- Bad: two live names per requirement for as long as the existing text is read.

### 3. Keep the agent-made format

- Good: no change at all.
- Bad: keeps a format the owner never chose, the NIST clash and the blocked prefixes.

## More Information

- **Evidence:** [../research/0014-number-requirements-req-nnnn.md](../research/0014-number-requirements-req-nnnn.md): batch RB-0072.
- Related records: D-0001, D-0003, D-0004, D-0006, D-0009.
