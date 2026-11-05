---
id: D-0026
title: Tell documentation from knowledge, keep knowledge in docs/knowledge/, and rename docs/research to docs/evidence
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
revisit-when: the Research repository is retired and its knowledge moves; a document fits neither store; the organization standard reaches a new major version; docs/knowledge/ needs material that cannot be public; or the decision records are refactored as a set
---

# Tell documentation from knowledge, keep knowledge in docs/knowledge/, and rename docs/research to docs/evidence

## Context and Problem Statement

On 2026-11-03 the owner stated that a repository's `docs/` folder is not a knowledge store or a research store. It may contain those things, but they are different, so the organization standard has to tell them apart. Earlier, on 2026-10-31, the owner asked that central-hub store knowledge of its own, in a structure set for it.

Central-hub had no place for its own knowledge, and its folder `docs/research/` used the knowledge store's word for decision summaries. On 2026-11-04 the owner chose to keep knowledge inside `docs/`, noting that `docs/` at the root is the usual home for written material in a repository.

The project is still greenfield. On 2026-11-04 the owner asked that records be changed in place while that lasts, with no orphans and no references to old paths.

## Decision Drivers

- **One test, the same answer from every agent.** A file goes to exactly one store.
- **Words mean one thing.** "Research" is the knowledge store's word.
- **One `docs/` folder at the root**, as most repositories have.
- **Change in place while greenfield.** No record of exceptions on top of another record, and no notes about old paths.
- **Public repository** (CLAUDE.md rule 4). Knowledge kept here is public.
- **Replaceable** (REQ-0011).

## Considered Options

1. **`docs/knowledge/`:** a store test, knowledge in `docs/knowledge/` laid out by the organization standard, and `docs/research/` renamed `docs/evidence/`.
2. **A root `knowledge/` folder** beside `docs/`, with the same test and rename.
3. **Step 0 only:** the store test, with no knowledge folder and no rename.

## Decision Outcome

Chosen option: **1**. The owner's own messages set it: on 2026-11-03 at 23:55 UTC, that documentation and knowledge are different and the standard must tell them apart; on 2026-11-04 at 02:12 UTC, that documentation belongs in `docs/` at the root and a root knowledge folder is not usual; and at 02:14 UTC, that records change in place while the project is greenfield. The owner then picked this plan on decision cards at 00:36 and 02:14 UTC. This record waits for the owner's acceptance under D-0001.

```text
docs/
├── PRD.md  architecture.md  glossary.md
├── decisions/  specs/  standards/  runbooks/  postmortems/  diagrams/
├── evidence/      one summary per decision record   (D-0016)
└── knowledge/     what we learned or gathered, laid out by the organization standard
```

### What changes, in place

1. **D-0012** gains rule 12, the store test: "Is it about this repository's system, saying why it is so, what it is, or how to run or change it?" If yes, D-0012's kind folders place it. If no, it goes in `docs/knowledge/`. Its tree shows `evidence/` and `knowledge/`, and rule 6 sends learning material to `docs/knowledge/`.
2. **D-0016** names `docs/evidence/` in rule 1. A record links its evidence file as `../evidence/NNNN-slug.md`.
3. **The same PR** renames `docs/research/` to `docs/evidence/` with `git mv`, rewrites every link, and updates the docs checks and `AGENTS.md`. No old path is kept anywhere it would be read as current.

### Rules for `docs/knowledge/`

1. **Layout.** It follows the organization standard. The standard's one home is the Research repository, `99-meta/ORGANIZE.md`. `docs/knowledge/99-meta/ORGANIZE.md` holds only a pointer to it and its version, never a copy.
2. **Creation.** The folder appears with its first real file (D-0012 rule 2), together with its README, the pointer file and a CI step that runs the standard's check on it.
3. **Checks.** The docs checks place files only by D-0012's kind patterns, so knowledge files get no record schema. Knowledge we wrote gets the same link and Markdown style checks as every other page. Captured material we did not write (`docs/knowledge/04-resources/`, `docs/knowledge/05-archive/`, and any `sources/` or `data/` folder inside it) is skipped by the style and link checks, as the standard's own check skips it.
4. **Names.** Files in `docs/knowledge/` follow the standard's naming rule, which allows no IDs or dates in names. Frozen records keep their `NNNN-` numbers (D-0003).
5. **No private material** (CLAUDE.md rule 4).

### Consequences

- Good: an agent decides between the two stores with one question, then uses one store's rules.
- Good: "research" names one thing, the knowledge store.
- Good: everything written about the repository stays under one root folder.
- Bad: two layouts live under `docs/`, so an agent has to read which store it is in.
- Neutral: nothing moves into `docs/knowledge/` until a real file needs it.

### Confirmation

- No link in the repository points to `docs/research/`, and the docs checks pass on this PR.
- The organization standard's check passes on `docs/knowledge/` from its first file.

## Pros and Cons of the Options

### 2. A root `knowledge/` folder

- Good: the docs checks and the knowledge check never see each other's files.
- Bad: a root folder that most repositories do not have, beside a `docs/` that already holds written material.

### 3. Step 0 only

- Good: no files move.
- Bad: "research" keeps two meanings, and central-hub still has no place for its own knowledge.

## More Information

- **Evidence:** [../evidence/0026-tell-documentation-from-knowledge.md](../evidence/0026-tell-documentation-from-knowledge.md).
- Related records: D-0001, D-0003, D-0012, D-0016.
