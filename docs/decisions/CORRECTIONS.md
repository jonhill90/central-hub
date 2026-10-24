# Corrections log

Every accepted record, evidence file and active standard is edited in place and reads as the current text (D-0006). This file has one line per change: the date, the record, what changed, and the PR with its approval facts (D-0016 rule 7) and merge commit. The text before a change is in git at the commit before that merge.

It has four parts: decision changes, which the owner accepts by name; ID changes, one line per change made during Foundation (D-0003 rule 5); folded and reused numbers; and corrections, which fix an error without changing what was decided.

## Decision changes in this PR (accepted with PR #42)

PR #42's approval facts and merge commit are added after it merges (D-0006 step 6).

- 2026-10-24 · D-0001, D-0006, D-0016 · a correction edits the record in place so it reads as the current text, and is logged as one line here. Records hold no Corrections sections and no before-and-after text. This applies from PR #42 · the owner's request of 2026-10-24, 05:52 to 05:57 UTC; it follows his 2026-10-16 08:25 UTC request to avoid near-copy records
- 2026-10-24 · D-0006 · a changed decision is made by a new record or, when the owner accepts it by name in a PR, in place, and is listed in this part; a record may be folded into another the same way · the owner's request of 2026-10-24, 05:52 to 05:57 UTC
- 2026-10-24 · D-0006 step 7 · `check` and `merged` in `accepted-evidence` may be corrected so they state what happened; the approval facts never change · the same request, that records read as current truth
- 2026-10-24 · D-0001 field contract, D-0019 check 1 · the `amends` and `amended-by` fields, which D-0006 added and no record uses now, are removed · follows the first line of this part
- 2026-10-24 · D-0003 rule 6 · a decision record folded into another keeps its number: it is never reused, and it is listed below · the owner's request of 2026-10-24, 05:52 to 05:57 UTC
- 2026-10-24 · D-0013, D-0017, D-0021 · folded into D-0012 (runbook steps), D-0016 rule 1 (`docs/research/`) and D-0019 rule 4 (linter settings), with their rules, reasons, considered options and revisit conditions; the files are removed · the same request
- 2026-10-24 · D-0003 rule 2 · a new family, or a change to a row (its home, who numbers it, or closing the family), is made by its own record, whose PR updates the row in D-0003 · the same request
- 2026-10-24 · D-0004 rule 5 · for a decision number, the tombstone is a line in the numbers list below, because the decisions index is generated (D-0001 "Index") · follows D-0003 rule 6 above
- 2026-10-24 · D-0010 rule 4 · the three replaced Research drafts no longer need a header line naming what replaced them · the owner's request of 2026-10-24, 05:52 to 05:57 UTC, for no retire or replace notes
- 2026-10-24 · D-0007, evidence 0007 · the reason for the PRD is the owner's yes to the 2026-10-19 decision card for a one-page PRD and frozen specs; the project brief is named as the coordinator agent's · the brief was agent-written, and the owner asked on 2026-10-24 that premises be checked
- 2026-10-24 · PRD goal 1 · start with one cluster in the home lab on Proxmox; one rented VPS joins it as an outside worker; cloud sites later · follows the owner's 2026-10-22 answer on the VPS's role
- 2026-10-24 · PRD goal 6 · everything is controllable from this repo; one-time console steps at the start are fine · follows the owner's 2026-10-14 statement on click-ops
- 2026-10-24 · D-0002 · the context, diagram and deployment target start with the home-lab cluster, as PRD goal 1 · follows the 2026-10-22 answer above
- 2026-10-24 · D-0011 · the "no click-ops" driver and its context read as PRD goal 6: controllable from this repo, one-time console steps at the start, and each job done by hand first (D-0012); the `hosts/` decision is unchanged · follows the 2026-10-14 statement above
- 2026-10-24 · D-0012 · a `manual` runbook may cover any job done by hand; the CKA scope applies to Kubernetes jobs · follows the owner's 2026-10-19 02:43 UTC request for a manual runbook first for each job, then an automated one
- 2026-10-24 · D-0003, D-0009, D-0014, D-0015, D-0018, D-0020 · the registry chain is unwound: D-0003 holds the family registry and its rules as current text; D-0003, D-0009, D-0014, D-0015 and D-0018 go from superseded to accepted, and D-0020 stays accepted; none has a supersede link, and each keeps only the family or rule change it adds, with its prefix check · the owner's request of 2026-10-24, 05:52 to 05:57 UTC, that records read as current truth with no supersede chains
- 2026-10-24 · STD-0002 rule 2 and its tables · which number each place gets is not chosen yet, and H, V and A stand for them; the place numbers, the "each place owns a /12" rule, the kept-empty block `10.0.0.0/10` and `10.64.0.0/11`, the spare rows and the approval fact for the numbers are removed; the home router's LAN range is moved out of the public file; one rule is added: when the place numbers are chosen, a range in the plan MUST NOT overlap another range in it · the owner voided the old place numbers, and asked for the home LAN range to be kept out of the public file, on 2026-10-24 between 05:40 and 05:56 UTC
- 2026-10-24 · Activation gate item 4 (AGENTS.md, CLAUDE.md), PR template · "a pinned, no-writer Flux install" now reads "a pinned, no-writer GitOps engine install (the engine is not chosen yet)", and the template asks what "the GitOps tool" will change · the engine was never put to the owner as a question, so no record chooses it
- 2026-10-24 · D-0019 rule 3 and check 4 · the word-check gate adds an owner-name rule (no first name under `docs/`, any case) beside the owner-quote rule, and both now gate every Markdown file a PR adds or changes, edited decision records and evidence files included; Markdown style still skips edits to existing records · records and evidence files are now edited in place (first line of this part), and D-0016 rule 5 says they never quote or name the owner
- 2026-10-24 · D-0001 field contract, D-0003 rule 5 and its diagram, decision schema · the `legacy-id` field is removed from every record and from the checks, with no replacement; after the Activation gate passes, an assigned ID never changes; each ID change made during Foundation is one line in this file, and records hold no note of the ID used before; the backlog links in D-0001 and D-0002 (BL-0111, BL-0112, BL-0119) are dropped, because each backlog row links to its record (D-0020) · the owner's request of 2026-10-24, 07:31 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNS3eJqhiebhJsDYg2RWM9Qn), for no records or docs that tell how IDs changed
- 2026-10-24 · D-0014, D-0015, D-0018, D-0020, evidence 0014, 0015, 0018, 0020 · each states only the current rule: the family it adds, its format, who numbers it, its register, and its reasons and options as they bear on that rule; the titles are shortened, and the files for D-0014 and D-0018 renamed to match (`0014-number-requirements-req-nnnn.md`, `0018-number-research-methods-rm-nnnn.md`); the ID changes they described are the lines under "ID changes" below · the same request

## ID changes

These IDs were changed during Foundation with the owner's approval (D-0003 rule 5). Each live file uses the current ID; the chat archive and git history keep the earlier ones.

- 2026-10-18 · research method IDs, first fix · agent-made method IDs fixed in the Research repo and the project files (batch RB-0055); the full list is in the project files' `research/method-id-fixes/CORRECTIONS.md`
- 2026-10-23 · requirements (D-0014) · `SR01` to `SR25` became `REQ-0001` to `REQ-0025`, same numbers; `SR16a` became `REQ-0016` and `SR16b` `REQ-0026`; the void `SR21` tombstone became `REQ-0021`; about 4,700 references, 63 of them in central-hub (PR #23); the full list is in the project files' `research/requirement-ids/CORRECTIONS.md` · the owner chose `REQ-0000` style at 03:38 UTC; D-0014 accepted with PR #22
- 2026-10-23 · research batches (D-0015) · the batch codes, 9 shapes such as `R3`, `RR1`, `R11b`, `ROUT-1`, `ADR-C1`, became `RB-0001` onward in order of SPEC date (ties by the SPEC.md's first commit; a SPEC with no date takes that commit's date); one batch under two folder names (`R1`, `DG1`) took one number, and aliases or parts of a batch (`RM2`, `R2b`) took that batch's number; the clashing `RR1`, `AT1` and `VN1` (about 280 citations) were read in context; scope: explicit batch citations, as the owner chose ("Rename clear batch citations") at 2026-10-23T04:34:26Z on the card asked at 04:32:58Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNC3LPUH1tBJdWGwRMxxkLn9), which measured about 23,000 matches of the code shapes; central-hub in PR #27; the full list is in the private research archive (batch RB-0074) · D-0015 accepted with PR #24
- 2026-10-23 · research methods (D-0018) · `RM01` to `RM122` became `RM-0001` to `RM-0122`, same numbers, by script over the Research repo and the project files (about 10,700 citations), skipping correction logs and kept records; the setup script with the updated research gate went to the owner in the same step; central-hub cited none · D-0018 accepted with PR #30
- 2026-10-24 · backlog items (D-0020) · the 24 decision-map rows missing from the backlog were added first (`D1` joined the repo-layout row, 14 open rows were added with their status, and 9 decided or applied rows as done); then every row, the 49 one-letter map codes (such as `D1`, `K1`, `S7`) and the 110 backlog labels, was numbered `BL-0001` onward in table order, by script, `BACKLOG.md:<label>` citations and the decision map included (about 370 and 280 citations); in central-hub, D-0001, D-0002 and the decisions index in PR #40 · D-0020 accepted with PR #38

## Folded and reused numbers

A folded decision number has no file and no row in the index, and is never used again (D-0003 rule 6). A reused number is a void entry's number given to a new item (D-0004).

- D-0006 (reused) · first used by the PR #9 draft, a full restatement of D-0005, closed unmerged on 2026-10-16; the owner approved the reuse under D-0004 on 2026-10-16 at 08:25 UTC. The current D-0006 was accepted with PR #10: approved 2026-10-16T08:28:58Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNTJTUNZbcPsUxG7TCKiX23s), head 0ae0493; merged as 0517ccf
- REQ-0021 (reused) · the void row was a usage limit for one agent product, dropped by the owner on 2026-10-13 at 04:23 UTC; at the owner's request (06:09 UTC) the next new requirement, shared vocabulary, took the number instead of `REQ-0022`, in Research commit `f63ae969`. The search found 6 files that meant the void entry (the 3 Rules table review files, the inbox row, Research `CURRENT-STATE.md` and the register's Dropped entry), and all 6 were updated or annotated; 3 frozen study files and 20 chat archives were left as records; reported to the owner in the Rules table thread at 06:13 UTC
- D-0013 · folded into D-0012. It was accepted with PR #21: approved 2026-10-23T03:42:38Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNWc7Mzu6ZFvoYgnxsDKVyKh), head eb33bd7; merged as 5f9fa76
- D-0017 · folded into D-0016 rule 1. It was accepted with PR #26: approved 2026-10-23T04:58:39Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNT1mFLf6eEyeGKAMDBbAKVd), head 5115dcd; merged as b852f90
- D-0021 · folded into D-0019 rule 4. It was accepted with PR #41: approved 2026-10-24T06:21:57Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNAqUPkvQ7d3ptmgAjUaDB92), head c62cf99; merged as 8c1b65e

## Corrections

- 2026-10-13 · D-0001 to D-0003 · spelling and punctuation of the owner's quoted words tidied; the quotes were later removed under D-0016 rule 5 · PR #6, merged as 398a268; it predates D-0006, and no approval facts were recorded
- 2026-10-17 · D-0005 · pillar 3 register rows, the exit path for AWS and Google, and the wording of rule 3 and of option "B" · PR #11: approved 2026-10-17T00:29:34Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNUkxQV8rtkCyFUjGmKo9bMr), head 59cb507; merged as 3791772
- 2026-10-23 · D-0004 to D-0012, PRD · requirement IDs respelled `REQ-NNNN` (D-0014) · PR #23: approved 2026-10-23T04:04:08Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF), head cabb14e; merged as 687b5db
- 2026-10-23 · D-0016 · two evidence links moved to `docs/research/` (D-0017) · PR #26: approved 2026-10-23T04:58:39Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNT1mFLf6eEyeGKAMDBbAKVd), head 5115dcd; merged as b852f90
- 2026-10-23 · D-0001 to D-0003, D-0005 to D-0009, D-0011, D-0012, D-0014, D-0016, evidence 0006 and 0016 · research batch codes respelled `RB-NNNN` (D-0015) · PR #27: approved 2026-10-23T04:59:42Z (cmsg_01X43rfNYp4H1dL1V2dkfkwN7qM5qKKp8HDEfuF6EYoQkC), head 8d63c29; merged as edac9fe
- 2026-10-23 · D-0006 · approval and the owner's words recorded in neutral form; evidence link added (D-0016) · PR #28: approved 2026-10-23T05:05:33Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNVpXFj2FM54dFP3zuszW4LF), head 6bbba58; merged as b3c2d9e
- 2026-10-23 · D-0001 to D-0005 · approval and the owner's words recorded in neutral form; evidence links added (D-0016) · PR #29: approved 2026-10-23T05:22:43Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNJe6kJE76z6YiJbQ9y7Tg3i), head 97fd304; merged as ba5bb20
- 2026-10-23 · D-0007 to D-0010 · approval and the owner's words recorded in neutral form; evidence links added (D-0016) · PR #31: approved 2026-10-23T05:50:25Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNDAeh1xBwykD4qgSUzJ1UcQ), head eca96c0; merged as 7915625
- 2026-10-23 · D-0011 to D-0015 · approval and the owner's words recorded in neutral form; evidence links added (D-0016) · PR #32: approved 2026-10-23T06:07:52Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNAnCf1qE6ULcTZw9foG87Mc), head f994dac; merged as 92dd9a2
- 2026-10-23 · D-0009, evidence 0008, D-0012 · front matter made valid YAML; D-0012's back-link field completed · PR #33: approved 2026-10-23T21:46:34Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNAaxwHhhgPt6cvkvmWyw9yy), head e6b7c1c; merged as 916a972
- 2026-10-24 · STD-0001, STD-0002 · approval recorded in neutral form (D-0016) · PR #34: approved 2026-10-24T01:49:14Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNHByoYueesp8x5JHxzxVb35), head ab5af17; merged as f07fe7e
- 2026-10-24 · D-0001, D-0002, decisions index · backlog labels respelled `BL-NNNN` (D-0020) · PR #40: approved 2026-10-24T02:50:34Z (cmsg_01X43rfNYp4H1dL1V2dkfkwN6ZL4axtSm9grZd8Kszxagb), head 1453cb1; merged as 33518e0

The lines below are PR #42's; its approval facts and merge commit are added after it merges.

- 2026-10-24 · D-0015 · the 2026-10-23 04:16 UTC card described without quoting it · PR #42
- 2026-10-24 · D-0001 · approval block and index text brought to the current rules (D-0016; the generated index) · PR #42
- 2026-10-24 · D-0019 · rule 4 states where the linter settings live, as D-0021 decided · PR #42
- 2026-10-24 · D-0004, D-0007, D-0008, D-0009, D-0010, D-0011, D-0012, D-0016, D-0019 · "Not decided" items that are settled elsewhere removed (by D-0008, D-0010, D-0019, and the standards register README accepted with STD-0001 in PR #16); stale acceptance lines removed; D-0010 title and file name shortened · PR #42
- 2026-10-24 · evidence 0012 · the runbook fields and status words described as accepted with the record · PR #42
- 2026-10-24 · D-0001 to D-0016, STD-0001, STD-0002 · Corrections sections removed; each is one line in this file, and the full text is in git before the PR #42 merge · PR #42
- 2026-10-24 · evidence 0002, 0003, 0006, 0020 · moved source URLs updated; the ICSA 2026 paper in 0006 linked by its full title · PR #42
- 2026-10-24 · evidence 0005 · the Azure sustainability source read on its live page; two source URLs updated · PR #42
- 2026-10-24 · evidence 0018 · the NIST source named as SP 800-53 Release 5.2.0, which added `SA-15(13)` · PR #42
- 2026-10-24 · STD-0001 · sources added for the hostname limits · PR #42
- 2026-10-24 · D-0011, D-0012 · STD-0002 named without the old "proposed" note · PR #42
- 2026-10-24 · D-0003, D-0004, D-0009, D-0014, D-0015, evidence 0003 · wording that told of earlier IDs replaced by the current text: the clash finding's examples, D-0004's context, option 2 and tombstone (the REQ-0021 reuse is now a line in the numbers list), the prefix check, the lifecycle finding, and the thread name in two `check` fields · PR #42
- 2026-10-24 · D-0006, D-0014, D-0016 · sentences that narrated earlier wording removed · PR #42
- 2026-10-24 · D-0001 to D-0020, STD-0001, STD-0002, decisions and standards READMEs, runbooks README · the owner named by role, not by first name, in the text and in `decision-makers` (D-0016 rule 5) · PR #42
- 2026-10-24 · D-0003 to D-0020, STD-0001, STD-0002 · `merged` names the merge commit, and `check` no longer refers to the removed quote · PR #42
- 2026-10-24 · D-0012, standards README, decisions README · D-0016 added to D-0012's related records; the `STD-` family cited at D-0003 rule 1; the index says where folded numbers are listed · PR #42
- 2026-10-24 · D-0010 · blank lines added around two option headings (Markdown style) · PR #42
- 2026-10-24 · D-0003, D-0004, D-0012, D-0015, PRD · stale wording brought to the current text: the D-0003 rule 6 heading, D-0004's count of reused IDs, the places D-0012 and the PRD say are not created yet · PR #42
- 2026-10-24 · STD-0002 · the home router's LAN row says the private store is not chosen yet (D-0012); the AWS and Google Cloud row has its place in the Place column · PR #42
- 2026-10-24 · D-0001, D-0002, D-0011 · personal details about the owner dropped from a driver, an option and a pro; the decisions are unchanged · PR #42
