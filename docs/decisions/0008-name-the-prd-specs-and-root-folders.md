---
id: D-0008
title: Name the PRD docs/PRD.md, keep specs in docs/specs/, and name root folders by job
status: accepted
date: 2026-10-19
decision-makers: [jon]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0007]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-19T04:04:03Z
  approved-commit: 86484af7821eaf32afc0407447f6a9b4ae84ce16
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNLjKFZhnGXTRAmEntnMMFcR
  approval-names: "PR #13 and head 86484af, in the message itself"
  check: the drafting agent read the message in the PRD and spec research thread at 2026-10-19T04:04Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #13, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: a second repo adopts the same standard; a root folder's tool is replaced; Kubernetes stops being the runtime; or a reader cannot find the PRD
---

# Name the PRD docs/PRD.md, keep specs in docs/specs/, and name root folders by job

## Context and Problem Statement

D-0007 settled which requirement documents exist. It left two points to a later decision: "the final folder and document names" and "whether the PRD sits at the repository root or under `docs/`" (D-0007, "Not decided here").

On 2026-10-18 Jon said yes to the repo layout: central-hub is system 8 Platform's repo, and its shared parts are sorted by job. The names in that layout were the drafting agent's own picks. No source chose them, and Jon had not yet confirmed them.

This record fixes those names. It does not create the folders.

## Decision Drivers

- **Name for the job, not the vendor product.** Jon said yes to this rule (and to naming clusters by role) on 2026-10-19 during his review of the organize-repository skill.
- **Keep the root short.** The repository root holds only what a reader needs before going deeper (README, AGENTS, SECURITY). Every document kind sits under `docs/`.
- **Fit accepted records.** D-0007 rule 3 already places specs in `docs/specs/`.
- **Replaceable** (REQ-0011).

## Considered Options

1. **The names below, with the PRD under `docs/`.**
2. **The same names, with `PRD.md` at the root** next to README. Some of Jon's earlier repos kept it there, treating it as an input to the work rather than documentation of it.
3. **Different names**, picked one by one.

## Decision Outcome

Chosen option: **1**. Jon said yes to the proposed names on 2026-10-19 at 04:01 UTC, on a decision card that asked: "Keep these central-hub names: docs/PRD.md, docs/specs/, and root folders private-network, hosts, kubernetes, dns, backup?" That answer chose the option. Jon accepted this record under D-0001 on 2026-10-19 at 04:04 UTC.

```
central-hub/
├── README.md  AGENTS.md  SECURITY.md
├── docs/
│   ├── PRD.md                    the one-page PRD (D-0007 rule 1)
│   ├── specs/YYYY-MM-<slug>.md   one spec per change (D-0007 rule 3)
│   ├── decisions/
│   └── runbooks/
├── private-network/              the tailnet policy, tags only
├── hosts/                        machines below Kubernetes
├── kubernetes/                   clusters/<role>/, infrastructure/<capability>/, apps/
├── dns/
└── backup/
```

### Rules

1. **PRD.** The PRD is `docs/PRD.md`. README and AGENTS link to it, so it stays within D-0007's two layers.
2. **Specs.** Specs live in `docs/specs/`, as D-0007 rule 3 says.
3. **Root folders.** The root folders for platform parts are `private-network/`, `hosts/`, `kubernetes/`, `dns/` and `backup/`.
   - Each one is named for its job, never for a vendor product.
   - `kubernetes/` is named for a tool on purpose. Kubernetes owns every file in it, so replacing Kubernetes would rewrite them all anyway.
4. **Clusters.** A cluster folder is named for its role, for example `kubernetes/clusters/main/`, never for the machine or provider it runs on.
5. **Creation.** A folder is created with its first real file. None is created empty.

### Not decided here

- the status words for specs;
- the names inside `kubernetes/infrastructure/` and any other new root folder;
- where vendor areas (labs) go;
- where per-system records live;
- the rest of the layout rules (organize-repository skill), which Jon reviews in that skill's own repo.

### Consequences

- Good: a reader or agent can tell from the name alone what a root folder holds.
- Good: replacing a vendor product leaves every root folder name unchanged.
- Bad: `kubernetes/` breaks the "never a vendor product" rule, as a stated exception.
- Bad: the PRD is one click further from the root than it would be at the top level.
- Neutral: none of these folders exists yet. Each one appears with its first file.

### Confirmation

- A reviewing agent checks each PR that adds a root folder or moves the PRD against this record.
- The PRD, once written, is at `docs/PRD.md`, and README links to it.

## Pros and Cons of the Options

### 2. PRD at the root
- Good: the PRD is visible on the repository's front page.
- Bad: the root grows a file that is neither an entry point nor an agent rule.

### 3. Different names
- Good: each name gets a separate look.
- Bad: no source picked different names, so the choice would have nothing new to rest on.

## More Information

- **Evidence:** [../research/0008-name-the-prd-specs-and-root-folders.md](../research/0008-name-the-prd-specs-and-root-folders.md): the repository layout batch RB-0036, and the names question kept in batch RB-0057.
- Related records: D-0001, D-0002, D-0003, D-0007.

## Corrections

- **2026-10-23** (requirement IDs respelled under D-0014): 1 requirement ID renamed, `SR11` to `REQ-0011`. Before: `SR11`; after: `REQ-0011`, and the same for each pair listed. Reason: D-0014 retires the `SR` spelling and its rule 5 renames live references in place; no decision changes. Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23).
- **2026-10-23** (research batch IDs under D-0015): 1 research batch citation renamed: `RL4` to `RB-0036`. Reason: D-0015 numbers research batches `RB-NNNN`, and its rule 5 renames live references in place; no decision changes. Approval: the owner, 2026-10-23T04:59:42Z (approval-ref cmsg_01X43rfNYp4H1dL1V2dkfkwN7qM5qKKp8HDEfuF6EYoQkC), naming PR #27 and head 8d63c29; approved commit 8d63c29543a8adccdebb9704146d067b238e1c54. Check: the drafting agent read the message at 2026-10-23T04:59Z and confirmed it names that PR and head.
- **2026-10-23** (owner's words and approvals recorded in neutral form under D-0016). Reason: D-0016 rules 5 to 7 and its "What happens to the existing records"; no decision changes. Where the text removed is the owner's words, this entry names where it was and a commit that holds it (ba5bb20) instead of copying it (D-0016 rule 7).
  1. `accepted-evidence` rewritten once into D-0016 rule 6 fields with D-0006 step 7's fixed mapping, as amended by D-0016: `timestamp` to `approved-at`, `message-id` to `approval-ref`, `quote-check` to `check`; `approved-by: owner` and `approval-names` added; `quote` removed (its text is in `accepted-evidence.quote` at commit ba5bb20). No value changes.
  2. Considered Options, option 2: a phrase quoted from a file in one of Jon's earlier repositories (at commit ba5bb20), treated here as the owner's words, replaced by a neutral summary. After: "Some of Jon's earlier repos kept it there, treating it as an input to the work rather than documentation of it."
  3. More Information, first bullet. Before: "Research behind the names: Research repo, `areas/documentation/research/prd-spec-ps3/NAMES-QUESTION.md` and the repo layout batch RB-0036 (`labs/central-hub/repo-layout/rl4/`)." After: "**Evidence:** [../research/0008-name-the-prd-specs-and-root-folders.md](../research/0008-name-the-prd-specs-and-root-folders.md): the repository layout batch RB-0036, and the names question kept in batch RB-0057." Reason: the old pointers are private; links the evidence file (D-0016 rule 1 as amended by D-0017).
  4. The 2026-10-23 requirement-ID entry above: its approval, which quoted the approval message (at commit ba5bb20), rewritten as D-0016 rule 6 facts. After: "Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23)." No value changes.

  Approval: the owner, 2026-10-23T05:50:25Z (approval-ref cmsg_01X43rfNYp4H1dL1V2dkfkwNDAeh1xBwykD4qgSUzJ1UcQ), naming PR #31 and head eca96c0; approved commit eca96c04520789ec785fc4fd584c8f37a3b429f9. Check: the drafting agent read the message at 2026-10-23T05:50Z and confirmed it names that PR and head.
