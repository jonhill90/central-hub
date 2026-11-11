---
id: D-0026
title: Tell documentation from knowledge, keep polished explanations in docs/explanations/, and rename docs/research to docs/evidence
status: accepted
date: 2026-11-04
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0012, D-0016]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-11-05T07:18:12Z
  approved-commit: bf085eae2fa04cfc57e32a1943e14af8bf743607
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNCYF3SKyBWQWXbhUNPppNvz
  approval-names: "D-0026 by its ID; neither the PR nor the head"
  check: the drafting agent read the message in its project thread at 2026-11-05T07:18Z; it names D-0026 and nothing else. PR #55 had already merged, and its head bf085ea and the merge commit c2e932c hold the same record, which was unchanged on main at the time of the message, so the record accepted is the one approved here. An independent check by a reviewing agent is still to do
  merged: jonhill90 merged PR #55 at 2026-11-04T03:16:15Z as c2e932c, before this acceptance
revisit-when: the agent notebook is retired and its knowledge moves; a document fits neither store; docs/explanations/ needs material that cannot be public; the organization standard reaches a new major version; or the decision records are refactored as a set
---

# Tell documentation from knowledge, keep polished explanations in docs/explanations/, and rename docs/research to docs/evidence

## Context and Problem Statement

On 2026-11-03 the owner stated that a repository's `docs/` folder is not a knowledge store or a research store. It may contain those things, but they are different, so the organization standard has to tell them apart. Earlier, on 2026-10-31, the owner asked that central-hub store knowledge of its own, in a structure set for it. On 2026-10-26 he asked that central-hub show the work in public: his progress, what he learns, and how the home lab grows (D-0013).

The agents keep their working knowledge in the agent notebook, `jonhill90/agent-notebook`: research, measurements, notes and thinking. The notebook is private. On 2026-11-08 the owner said central-hub must rebuild and be trusted from the repository alone, with its provenance in it, and without the noise of the notebook. On 2026-11-10 he said central-hub holds the public-facing, polished version of the knowledge.

Central-hub's folder `docs/research/` also used the knowledge store's word for decision summaries.

The project is still greenfield. On 2026-11-04 the owner asked that records be changed in place while that lasts, with no orphans and no references to old paths.

## Decision Drivers

- **One test, the same answer from every agent.** A file goes to exactly one store.
- **Words mean one thing.** "Research" is the knowledge store's word.
- **One `docs/` folder at the root, with one layout,** sorted by kind of document (D-0012).
- **The repository stands alone.** It rebuilds and is trusted without the notebook, and it shows the work in public (D-0013).
- **Change in place while greenfield.** No record of exceptions on top of another record, and no notes about old paths.
- **Public repository** (CLAUDE.md rule 4). Everything kept here is public.
- **Replaceable** (REQ-0011).

## Considered Options

1. **`docs/knowledge/`:** a store test, knowledge in `docs/knowledge/` laid out by the organization standard, and `docs/research/` renamed `docs/evidence/`.
2. **A root `knowledge/` folder** beside `docs/`, with the same test and rename.
3. **Step 0 only:** the store test, with no knowledge folder and no rename.
4. **`docs/explanations/`:** the store test, the rename, working knowledge in the agent notebook, and the polished version of what was learned about this system in one more kind folder, `docs/explanations/`.

## Decision Outcome

Chosen option: **4**. The owner's own messages set it:

- 2026-11-03 23:55 UTC: documentation and knowledge are different, and the standard must tell them apart.
- 2026-11-04 02:12 UTC: documentation belongs in `docs/` at the root, and a root knowledge folder is not usual.
- 2026-11-04 02:14 UTC: records change in place while the project is greenfield.
- 2026-11-09 00:29, 00:36 and 00:45 UTC: documentation still goes into the repositories; the notebook is the agents' brain and the docs in the repository are for its readers; central-hub rebuilds without the notebook and carries its own provenance.
- 2026-11-10 21:52 UTC: the repository holds the public-facing, polished version.
- 2026-11-11, decision cards in the owner's project thread: a finding gets its polished version here once it is proven, by a pull request the owner sees (02:18 UTC); central-hub never links into the notebook (02:29 UTC); polished explanations and lessons go in one kind folder, `docs/explanations/`, not `docs/knowledge/` (02:38 UTC).

Option 1 was chosen first, on 2026-11-04. `docs/knowledge/` was never made. This change waits for the owner's acceptance under D-0001.

```text
docs/
├── PRD.md  architecture.md  glossary.md
├── decisions/  specs/  standards/  runbooks/  postmortems/  diagrams/
├── evidence/        what a decision rests on             (D-0016)
└── explanations/    how a part works, and what we learned  (this record)
```

### What changes, in place

1. **D-0012** gains rule 12, the store test: "Is it about this repository's system, saying why it is so, what it is, or how to run or change it?" If yes, D-0012's kind folders place it. If no, it goes in the agent notebook. Its tree shows `evidence/` and `explanations/`, and rule 6 sends learning material about this system to `docs/explanations/`.
2. **D-0016** names `docs/evidence/` in rule 1. A record links its evidence file as `../evidence/NNNN-slug.md`.
3. **The same PR** renames `docs/research/` to `docs/evidence/` with `git mv`, rewrites every link, and updates the docs checks and `AGENTS.md`. No old path is kept anywhere it would be read as current.

### Rules

1. **Two stores.** Working knowledge (research, measurements, notes, thinking, noise) lives in the agent notebook, laid out by that repository's `99-meta/ORGANIZE.md`. This repository keeps no copy of that standard.
2. **What `docs/explanations/` holds.** Pages that explain how a part of this system works, what building or running it taught us, and how the platform has grown. A page that says how to do a job is a runbook, and the research behind one decision is its evidence file, so neither goes here.
3. **Proven before it is published.** A notebook finding about this system gets its polished page here once it is measured or sourced, by a pull request the owner sees, like every other document.
4. **The repository stands alone.** A page here carries its own sources and measurements and never links into the notebook, which is private. The notebook may link to pages here, and never copies their steps.
5. **Creation.** `docs/explanations/` appears with its first real page, with its README and its row in `AGENTS.md` (D-0012 rule 2).
6. **No private material here** (CLAUDE.md rule 4).

### Consequences

- Good: an agent decides between the two stores with one question, then uses one store's rules.
- Good: "research" names one thing, the knowledge store.
- Good: `docs/` keeps one layout, by kind of document, and "explanation" is a common documentation term.
- Good: the learning the owner wants to show has a public home, without the notebook's noise.
- Bad: a finding is written twice, once as a working note and once as a polished page, and the two can drift. Rule 3 keeps the polished page tied to a proof.
- Neutral: nothing goes into `docs/explanations/` until a proven finding needs it.

### Confirmation

- No link in the repository points to `docs/research/` or `docs/knowledge/`, and the docs checks pass on this PR.
- No page here links into the agent notebook.

## Pros and Cons of the Options

### 1. `docs/knowledge/`

- Good: everything written about the repository stays under one root folder.
- Bad: two layouts live under `docs/`, so an agent has to read which store it is in, and the notebook's working layout would sit in a public, polished repository.

### 2. A root `knowledge/` folder

- Good: the docs checks and the knowledge check never see each other's files.
- Bad: a root folder that most repositories do not have, beside a `docs/` that already holds written material.

### 3. Step 0 only

- Good: no files move.
- Bad: "research" keeps two meanings, and central-hub still has no place for what it has learned.

## More Information

- **Evidence:** [../evidence/0026-tell-documentation-from-knowledge.md](../evidence/0026-tell-documentation-from-knowledge.md).
- Related records: D-0001, D-0003, D-0012, D-0013, D-0016.
