---
id: D-0017
title: Keep each record's evidence file in docs/research/, not in a folder beside the record
status: proposed
date: 2026-10-23
decision-makers: [jon]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0012, D-0016]
supersedes: []
superseded-by:
amends: [D-0012, D-0016]
accepted-evidence:
legacy-id: []
revisit-when: a knowledge system is chosen that should hold research summaries; or a record needs more than one supporting file
---

# Keep each record's evidence file in docs/research/, not in a folder beside the record

## Context and Problem Statement

D-0016 rule 1 puts each record's evidence file in a folder named like the record, inside `docs/decisions/`: `docs/decisions/NNNN-slug/evidence.md`. After D-0016 merged, two such folders sat in the decisions folder, one for D-0006 and one for D-0016.

On 2026-10-23 the owner asked for the evidence files to move out of `docs/decisions/` into a directory of their own, so that the decisions folder does not mix record files with folders. The owner suggested a research directory and asked for options.

This record decides where evidence files live. What an evidence file holds, and every other D-0016 rule, stays as it is.

## Decision Drivers

- **The decisions folder holds records only.** A reader listing `docs/decisions/` sees one file per decision and the index.
- **One place per kind of document** (D-0012 rule 1).
- **The evidence stays easy to find from its record.** Each record links its evidence file.
- **Replaceable** (REQ-0011).

## Considered Options

1. **`docs/research/`**, one file per record, named like the record.
2. **`docs/evidence/`**, the same, under a name that cannot be confused with the private research repository.
3. **`docs/decisions/evidence/`**, one folder inside the decisions folder holding every evidence file flat.
4. **No evidence files:** each record lists its public sources under More Information.
5. **Keep D-0016 rule 1:** a folder beside each record.

## Decision Outcome

Chosen option: **1**.

```
docs/
├── decisions/
│   ├── 0006-allow-corrections-to-accepted-records.md      the record
│   └── README.md
└── research/
    ├── 0006-allow-corrections-to-accepted-records.md      its evidence file
    └── README.md
```

### Rules

1. **Place.** A record's evidence file is `docs/research/NNNN-slug.md`, with the same file name as its record in `docs/decisions/`. This replaces the path in D-0016 rule 1. Everything else in D-0016 rule 1, and rules 2 to 7, are unchanged.
2. **Kind.** `docs/research/` is a kind folder under D-0012: "what a decision rests on", frozen, as records are. It holds only evidence files built under D-0016 rule 3. It is not a copy of the research batches, which stay outside this repository (D-0016 option 3; D-0012 rule 6 still keeps learning material out of `docs/`).
3. **Index.** `docs/research/README.md` lists each evidence file with its record, as D-0012 rule 4 asks of every kind folder.
4. **Links.** A record links its evidence file under More Information as `../research/NNNN-slug.md`. The evidence file's front matter names its record by ID.
5. **Corrections.** An evidence file is frozen with its record. It changes only by a correction under D-0006, listed in its record's Corrections section.

### Changes to D-0012 and D-0016

- **D-0012**, the docs map: gains the line `research/  what a decision rests on  frozen  (D-0016, D-0017)`, after `decisions/`. D-0012's `amended-by` becomes `[D-0017]`.
- **D-0016**, rule 1: the path `docs/decisions/NNNN-slug/evidence.md` becomes `docs/research/NNNN-slug.md`, and "in a folder named like the record" becomes "with the same file name as the record". D-0016's `amended-by` becomes `[D-0017]`.
- The bodies of D-0012 and D-0016 stay as they are, as D-0006 did for D-0001.

### What changes in this PR

- The two evidence files move from `docs/decisions/0006-allow-corrections-to-accepted-records/evidence.md` and `docs/decisions/0016-give-records-an-evidence-file-and-neutral-approval/evidence.md` to `docs/research/`, with their content unchanged.
- D-0016's two More Information links point to the new paths. That is a broken-link fix, so it is a correction under D-0006, listed in D-0016's Corrections section.
- `docs/research/README.md` is added, and its row is added to the AGENTS.md "Where to look" table (D-0012 rule 2).

### Consequences

- Good: `docs/decisions/` holds only record files and its index again.
- Good: evidence files are one folder, so they can be read, checked or moved to a future knowledge system together.
- Bad: a record and its evidence file are in two folders, so each link needs `../research/`.
- Bad: the name `research` is also the name of the private research repository. The folder's README says what it holds and that the batches are not here.
- Neutral: practice varies. Backstage keeps a decision record's supporting file in a separate tree, `docs/assets/architecture-decisions/`. MADR keeps supporting files flat beside its records. Python PEPs, Rust RFCs and Kubernetes KEPs use a folder per document ([D-0016's evidence](../research/0016-give-records-an-evidence-file-and-neutral-approval.md), finding 7).

### Confirmation

- `docs/decisions/` has no subfolders.
- Every file in `docs/research/` has a record with the same file name, and that record links it.
- The `docs/research/README.md` index lists every file in the folder.

## Pros and Cons of the Options

### 2. `docs/evidence/`
- Good: no confusion with the private research repository.
- Bad: the owner suggested `research`, and the files are summaries of research.

### 3. `docs/decisions/evidence/`
- Good: no new kind folder, so D-0012 is not changed.
- Bad: the decisions folder still holds a subfolder, which is what the owner asked to avoid.

### 4. No evidence files
- Good: one file per decision, nothing else.
- Bad: drops the findings, checks and limits, which D-0016 chose to include.

### 5. Keep D-0016 rule 1
- Good: no work.
- Bad: a folder per record in `docs/decisions/`, which the owner asked to change.

## More Information

- **Research:** none beyond D-0016's. The two layout facts above were read on 2026-10-23 from public repositories: `backstage/backstage` at d723272 (`docs/assets/architecture-decisions/catalog-core-entities.png`, linked from `docs/architecture-decisions/adr005-catalog-core-entities.md`) and `adr/madr` at ba75bb1 (`docs/decisions/0008-example-table.png` and others, flat beside the records).
- **Exit path:** to move evidence files elsewhere, a new record amends this one and the files move together; to drop them, a new record supersedes D-0016.
- **Related records:** D-0012, D-0016.
