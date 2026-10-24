---
id: D-0012
title: Sort docs/ by kind of document, add runbooks, architecture, glossary, postmortems and diagrams with their first file, and keep plans and playbooks out
status: accepted
date: 2026-10-23
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0007, D-0008, D-0009, D-0010]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-23T02:18:39Z
  approved-commit: ffd8dca206771f391fd5bb71415778a77a228db2
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNUAoAvcmynir2k9d41h2F3m
  approval-names: "PR #19 and head ffd8dca, in the message itself"
  check: the drafting agent read the message in the documentation path thread at 2026-10-23T02:18Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #19 merged at 2026-10-23T02:19Z as 007ee02, with this evidence commit on top of the approved commit
revisit-when: a kind folder passes about 30 files; a second reader group (not the owner or agents) needs its own docs; a docs site is built; the secret store for private values is chosen; a document kind turns up that fits no folder here; why lines in runbook steps grow into paragraphs; ※ links break often enough to need a link check; or every manual runbook has an automated twin and the manual ones stop being run
---

# Sort docs/ by kind of document, add runbooks, architecture, glossary, postmortems and diagrams with their first file, and keep plans and playbooks out

## Context and Problem Statement

D-0008 names `docs/PRD.md`, `docs/specs/`, `docs/decisions/` and `docs/runbooks/`. D-0009 adds `docs/standards/`. D-0011 leaves the folders inside `docs/` to the documentation folder map work.

On 2026-10-22 at 06:58 UTC the owner asked which folders central-hub needs for plans, specs, runbooks, architecture and any other kind of document that each likely scenario calls for. He also raised the runbook format as open. On 2026-10-19 at 02:43 UTC the owner had asked that a runbook explain why each step is done, briefly, and how the steps connect, so it reads like a story with reminders that link back; and that each job get a manual runbook first and an automated one later, because starting with the abstractions would hide what they are worth.

This record sets which kinds of document central-hub keeps, where each one goes, and the minimum content of a runbook and a postmortem. It creates no folder.

## Decision Drivers

- **A reader or agent can tell from the folder whether a file may be edited.** Some kinds are living (kept current). Others are frozen records (history).
- **Fit accepted records.** Nothing in D-0007, D-0008, D-0009, D-0010 or D-0011 changes.
- **Two layers (D-0007).** Every document is one link from README or AGENTS.md.
- **Public repository** (CLAUDE.md rule 4). Runbooks and postmortems tend to collect hostnames, addresses and contacts.
- **Replaceable** (REQ-0011). Each folder has a stated way to drop it.

## Considered Options

1. **Folders by kind of document** (decisions, specs, runbooks, postmortems), with each page shaped by the reader's need.
2. **Folders by reader need at the top** (Diátaxis: tutorials, how-to, reference, explanation).
3. **Docs by subject, next to the code** (`dns/README.md`, `hosts/README.md`), with no kind folders.

## Decision Outcome

Chosen option: **1**, with option 3's part READMEs added on top. The owner said yes to writing this map as a decision record on 2026-10-23 at 02:13 UTC, and accepted this record under D-0001 on 2026-10-23 at 02:18 UTC.

No standard or paper names docs folders. ISO/IEC/IEEE 15289 and ISO/IEC 20000-1 say layout is out of their scope, and no paper read tests a folder scheme. In the repos read, 12 of the 18 that have docs give decisions, proposals, runbooks or postmortems a folder of their own, even where their guides are sorted another way. Only 2 of 18 use Diátaxis at the top. Diátaxis itself says it is "not a scheme into which documentation must be placed - four boxes". (Batch RB-0069, [evidence](../research/0012-sort-docs-by-kind-of-document.md).)

```
central-hub/
├── README.md  AGENTS.md  SECURITY.md
├── docs/
│   ├── PRD.md              what the platform is for                 living   (D-0007, D-0008)
│   ├── architecture.md     how the parts fit today                  living   new
│   ├── glossary.md         what our words mean                      living   new
│   ├── specs/              one plan per change                      frozen   (D-0007, D-0010)
│   ├── decisions/          why we chose something                   frozen   (D-0001)
│   ├── research/           what a decision rests on                 frozen   (D-0016)
│   ├── standards/          the rule in force now                    living   (D-0009)
│   ├── runbooks/           how to do one job, step by step          living   (D-0008)
│   ├── postmortems/        what went wrong and what changed         frozen   new
│   └── diagrams/           drawing source files only                living   new
└── <each root folder>/README.md   what this part is, the record that owns it, its runbooks
```

### Rules

1. **Kinds and places.** Each kind of document goes in the place shown above, and nowhere else.
2. **Creation.** Each new file or folder appears with its first real file (D-0008 rule 5). The PR that adds it also adds its row to the AGENTS.md "Where to look" table, so it stays one link away (D-0007).
3. **One file until it grows.** `architecture.md` and `glossary.md` stay single files. A file becomes a folder of the same name, with a README, only when a second document on that kind arrives.
4. **Every kind folder has a README** that indexes it, as `decisions/`, `specs/` and `standards/` do now.
5. **Part READMEs.** Each root folder (`hosts/`, `kubernetes/`, `dns/`, `backup/`, `private-network/`) gets a `README.md` with its first file. It says what the part does, which decision record owns it, how it is dropped, and which runbooks run it. It points to records and never copies them.
6. **Not folders.** There is no `plans/` folder: a plan for one change is a spec (D-0007), and the ordered backlog stays outside this repo. There is no `playbooks/` folder: a response to an alert is a runbook whose trigger is that alert. There are no `how-to/`, `tutorials/` or `reference/` folders: runbooks are the how-tos, learning material stays in the Research repo, and generated reference stays next to the code it describes.
7. **Decisions folder name.** It stays `docs/decisions/` (MADR, D-0001), not `docs/adr/`.
8. **Glossary is the one source** for platform terms (REQ-0005). Other copies point to it. Terms about systems other than system 8 stay in the Research repo.
9. **Diagrams.** A drawing written as text stays inside the page that uses it. `docs/diagrams/` holds only source files such as `.d2`, `.drawio` or `.svg`.
10. **No private values in any document.** Hostnames, single machine addresses, contacts and secrets are never written here. A document names the key that holds the value in the private store, never the value (CLAUDE.md rule 4; STD-0002).
11. **Security postmortems wait.** A postmortem for a security incident stays in a private GitHub security advisory until the fix is out, and only then lands in `docs/postmortems/` (SECURITY.md).

### Runbook format

A runbook is a page for one job, named for the task: `docs/runbooks/<verb>-<object>.md`. When `docs/runbooks/` is created, its README carries this template.

```markdown
---
title: <task, verb first>
status: draft            # draft | tested | superseded | retired
kind: manual             # manual | automated
trigger: <alert, schedule, event, or "on request">
runner: <the owner, or an agent lane>
outcome: <what is true when it is done>
needs: <tools and permissions>
private-values: [<key names in the private store; never the values>]
files: [<paths this runbook runs or reads>]
last-tested: <YYYY-MM-DD, who ran it, on what>
superseded-by:
---

# <title>

## Before you start
<check the current state; stop if it is not what this runbook expects>

## Steps
1. <one action: the exact command, or a link to the script>
   why: <one or two sentences: why this step, and how it connects to the last one>
   ※ <optional: what this relies on, linked to where it is explained>
   expect: <what you should see>

## If it fails
<where to stop, how to undo, and when to tell the owner>

## Afterwards
<what to record and where: a postmortem after an incident, a spec's done-evidence after a build>

## Related
<the decision, spec, standard or postmortem behind it>
```

**Runbook status words.** `superseded` and `retired` mean what they mean for specs and standards (D-0010, D-0009). `tested` is the one new word. A runbook is living, so `accepted` would not say whether it still works, and `tested` does. These are the rules for setting it:
- Only a PR that records a replay on a fresh machine sets `tested`. That PR fills `last-tested` with the date, who ran it, and a link to the output.
- Any later change to the steps puts the runbook back to `draft` until it is replayed.
- The owner merges every one of these PRs, as he does every PR.

**Runbook steps.**
- **Why per step.** Each step in `## Steps` has a `why:` line of one or two sentences, between the action and `expect:`.
- **※ links back.** When a step relies on something explained in an earlier step or another document, it carries a `※` reminder that links there, for example `※ the pod network range was set in step 3`. A ※ link points to a step anchor or a document, never to a line number.
- **Reads like a story.** The steps run in the order the work happens, and each why says how the step connects to the one before.
- **Manual or automated.** A `manual` runbook does each step by hand; for a Kubernetes job, its scope is what the CKA exam tests. An `automated` runbook runs the same job through code in this repo, and links the `manual` runbook it replaces under Related.
- **Manual first.** For any job, the `manual` runbook is written and `tested` before its `automated` runbook is written.

### Postmortem format

A postmortem is one file per incident, `docs/postmortems/YYYY-MM-DD-<slug>.md`. Its front matter holds `date`, `status` and `runbook`. `status` is `proposed` or `accepted`, and the owner accepts a postmortem the same way as a decision record (D-0001). `runbook` is required and links the runbook that fixes or prevents the incident.

The sections are: Summary, Impact, How we found out, Timeline, Causes, What fixed it, Actions and Lessons. Each action links a runbook, spec or decision. After `accepted`, the body is not edited.

### Not decided here

- which private store holds the values that runbooks name, which waits on the secrets backend decision;
- a root `LICENSE` file;
- where "current state and next step" (REQ-0006) and the requirement rows live once the Research repo goes away;
- a changelog, which waits on the versioning decision;
- recordings of runbooks (for example VHS), and a docs site in its own repository.

### Consequences

- Good: an agent can tell from the folder alone whether a file is a living page or a frozen record.
- Good: the PRD's success signal, "rebuilt from this repo and its runbooks alone", gets a fixed runbook shape to check against.
- Good: every kind and folder can be dropped on its own. A folder is deleted, git keeps its history, and `superseded` and `retired` cover single files.
- Good: a runbook teaches as well as instructs, and the `kind` field shows which jobs are still manual.
- Bad: runbooks can't be used for a real rebuild until the private store is chosen, because their values live there.
- Bad: why lines make runbooks longer and can go stale when steps change. A step edit already puts the runbook back to `draft`, so the whys are re-read at the next replay.
- Bad: skills and tools trained on public repos expect `docs/adr/`, so agents need to be told `docs/decisions/` (AGENTS.md already says so).
- Neutral: each new place appears with its first file.

### Confirmation

- A reviewing agent checks each PR that adds a file under `docs/` or a root folder README against these rules.
- No `plans/`, `playbooks/`, `how-to/`, `tutorials/`, `reference/` or `adr/` folder appears under `docs/`.
- Each new place has its row in the AGENTS.md "Where to look" table.
- Each runbook has a `kind` value and a `why:` line on every step, and an `automated` runbook links a `tested` `manual` one.

## Pros and Cons of the Options

### 2. Folders by reader need (Diátaxis) at the top
- Good: a well-known scheme, used by the Kubernetes website and one homelab repo read.
- Bad: it has no place for decision records, specs, standards or postmortems, which are most of this repo's documents.
- Bad: it would move the three kind folders that already exist.

### 3. Docs by subject next to the code only
- Good: readers look in folder READMEs first. In 25 popular repos, nested READMEs held about 19% of feature docs and `docs/` folders about 3%.
- Bad: records that cross parts, such as decisions, specs and postmortems, would have no home. That is why rule 5 adds part READMEs on top of option 1, rather than replacing it.

### Runbook steps: one why section at the top of each runbook
- Good: shorter.
- Bad: the reader has to hold the reasons in mind and match them to steps, which is what the owner asked to avoid.

### Runbook steps: no change, with the whys only in the linked decision records
- Good: nothing to add.
- Bad: it misses the owner's 2026-10-19 request for a reason on every step.

## More Information

- **Evidence:** [../research/0012-sort-docs-by-kind-of-document.md](../research/0012-sort-docs-by-kind-of-document.md): batch RB-0069, with the map tested on 5 real items, a recall check, a devil's advocate pass and an independent claim check.
- Sources it rests on:
  - AWS Well-Architected OPS07-BP03, the runbook template;
  - NIST SP 800-34 Rev. 1 chapter 4, for steps, escalation and validation;
  - NIST SP 800-61r3, which treats incident records as frozen evidence;
  - MADR 4.0.0, for `docs/decisions/`;
  - Diátaxis;
  - the RULES-v4 R1 runbook fields (trigger, runner, files).
- Related records: D-0001, D-0007, D-0008, D-0009, D-0010, D-0011, D-0016. Related standard: STD-0002.
