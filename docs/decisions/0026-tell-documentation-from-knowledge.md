---
id: D-0026
title: Tell documentation from knowledge, rename docs/research to docs/evidence, and add a knowledge/ store laid out by the organization standard
status: proposed
date: 2026-11-04
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0008, D-0012, D-0016]
supersedes: []
superseded-by:
revisit-when: the Research repository is retired and its knowledge moves; a document fits neither store; the organization standard reaches a new major version; knowledge/ needs material that cannot be public; or docs/evidence/ holds anything other than one summary per record
---

# Tell documentation from knowledge, rename docs/research to docs/evidence, and add a knowledge/ store laid out by the organization standard

## Context and Problem Statement

On 2026-11-03 the owner stated that a repository's `docs/` folder is not a knowledge store or a research store. It may contain those things, but they are different, so the organization standard has to tell them apart. The owner also said the `docs/` layout in central-hub is not settled, and asked what the agents propose. Earlier, on 2026-10-31, the owner asked that central-hub start storing knowledge of its own, in a structure set for it.

D-0012 already keeps learning material out of `docs/` (rule 6). But the folder `docs/research/` uses the same word as the knowledge store, and central-hub has no place for knowledge of its own.

This record sets the test that sends a file to one store or the other, renames `docs/research/` to `docs/evidence/`, and adds a root folder `knowledge/`. It creates no folder and moves no file. That work is one PR after acceptance.

## Decision Drivers

- **One test, the same answer from every agent.** A file goes to exactly one store.
- **Words mean one thing.** "Research" is the knowledge store's word. A folder of decision summaries should not share it.
- **Fit accepted records.** D-0012's kind folders, D-0016's one evidence file per record and D-0008's job-named root folders stay.
- **Public repository** (CLAUDE.md rule 4). Knowledge kept here is public.
- **Replaceable** (REQ-0011). Each part has a stated way to drop it.

## Considered Options

1. **Two stores with a step 0 test:** `docs/` keeps D-0012, `docs/research/` becomes `docs/evidence/`, and `knowledge/` is a new store laid out by the organization standard.
2. **Step 0 only:** keep `docs/` exactly as D-0012 says, and add no `knowledge/` folder.
3. **One store:** lay out `docs/` by the organization standard too, replacing D-0012's kind folders.

## Decision Outcome

Chosen option: **1**. The owner chose this plan on a decision card on 2026-11-04 at 00:36 UTC. The card asked: "Use this plan for central-hub docs/ and its own knowledge?" This record waits for the owner's acceptance under D-0001.

```text
central-hub/
├── docs/              documentation store: about this repo's system   (D-0012)
│   ├── PRD.md  architecture.md  glossary.md
│   ├── decisions/  specs/  standards/  runbooks/  postmortems/  diagrams/
│   └── evidence/      one summary per decision record   (was research/, D-0016)
└── knowledge/         knowledge store: what we learned or gathered   new
    ├── README.md
    ├── 00-inbox/  01-notes/  02-projects/  03-areas/  04-resources/  05-archive/
    └── 99-meta/ORGANIZE.md   pointer to the organization standard
```

### Rules

1. **Step 0, the store test.** Ask: "Is it about this repository's system, saying why it is so, what it is, or how to run or change it?" If yes, it belongs in `docs/` and D-0012 places it. If no, it is knowledge and belongs in `knowledge/`.
2. **`docs/evidence/`.** `docs/research/` is renamed `docs/evidence/`. D-0016 rule 1 reads `docs/evidence/NNNN-slug.md` from then on, and a record links its evidence file as `../evidence/NNNN-slug.md`. Every other D-0016 rule stays. The change is listed in `CORRECTIONS.md` under D-0006.
3. **`knowledge/`, a new root folder.** It is added to the root folders of D-0008 rule 3. It is named for its job, and it appears with its first real file (D-0008 rule 5).
4. **Layout of `knowledge/`.** It follows the organization standard. Its one home is the Research repository, `99-meta/ORGANIZE.md`. `knowledge/99-meta/ORGANIZE.md` holds only a pointer to that file and its version, never a copy. The standard's check runs on `knowledge/` in CI once the folder exists.
5. **Names.** Frozen records in `docs/` keep their `NNNN-` numbers, because they are cited by ID (D-0003). Living pages are named by slug. Files in `knowledge/` follow the standard's naming rule, which allows no IDs or dates in names.
6. **No private material.** `knowledge/` is public like the rest of the repository. Private material stays out of it (CLAUDE.md rule 4).

### Order of work after acceptance

1. One PR does three things: it renames `docs/research/` to `docs/evidence/` with `git mv`, rewrites every link to it by script, and updates `.github/docs-check/` (its schemas and paths) and `AGENTS.md`.
2. `knowledge/` is made with its first real file, together with its README, the pointer file and the check step.

### Consequences

- Good: an agent decides between the two stores with one question, then uses one store's rules.
- Good: "research" names one thing, the knowledge store.
- Good: central-hub gets a home for its own knowledge before the Research repository is retired.
- Bad: the rename touches about 40 files that link `docs/research/`. A scripted rewrite and the link check cover it.
- Bad: two layouts live in one repository, so an agent has to read which store it is in.
- Neutral: nothing moves into `knowledge/` until a real file needs it.

### Confirmation

- A reviewing agent checks the rename PR: there are no links left to `docs/research/`, and the docs checks pass.
- The organization standard's check passes on `knowledge/` from its first file.

## Pros and Cons of the Options

### 2. Step 0 only

- Good: no files move.
- Bad: "research" keeps two meanings, and central-hub still has no place for its own knowledge.

### 3. One store

- Good: one layout in the repository.
- Bad: it drops D-0012's kind folders. Those match what 12 of 18 repositories with docs do, and they show whether a file is living or frozen.
- Bad: decision records, specs and runbooks would have to fit a layout made for notes and captured sources.

## More Information

- **Evidence:** [../research/0026-tell-documentation-from-knowledge.md](../research/0026-tell-documentation-from-knowledge.md).
- Related records: D-0001, D-0003, D-0006, D-0008, D-0012, D-0016.
