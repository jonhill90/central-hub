# Corrections log

Every accepted record, evidence file and active standard is edited in place and reads as the current text (D-0006). This file has one line per change: the date, the record, what changed, and the PR with its approval facts (D-0016 rule 7) and merge commit. The text before a change is in git at the commit before that merge.

It has three parts: decision changes, which the owner accepts by name; folded and reused numbers; and corrections, which fix an error without changing what was decided.

## Decision changes in this PR (accepted with PR #42)

PR #42's approval facts and merge commit are added after it merges (D-0006 step 6).

- 2026-10-24 · D-0001, D-0006, D-0016 · a correction edits the record in place so it reads as the current text, and is logged as one line here. Records hold no Corrections sections and no before-and-after text. This applies from PR #42 · the owner's request of 2026-10-24, 05:52 to 05:57 UTC; it follows his 2026-10-16 08:25 UTC request to avoid near-copy records
- 2026-10-24 · D-0006 · a changed decision is made by a new record or, when the owner accepts it by name in a PR, in place, and is listed in this part; a record may be folded into another the same way · the owner's request of 2026-10-24, 05:52 to 05:57 UTC
- 2026-10-24 · D-0006 step 7 · `check` and `merged` in `accepted-evidence` may be corrected so they state what happened; the approval facts never change · the same request, that records read as current truth
- 2026-10-24 · D-0001 field contract, D-0019 check 1 · the `amends` and `amended-by` fields, which D-0006 added and no record uses now, are removed · follows the first line of this part
- 2026-10-24 · D-0003 rule 6 · a decision record folded into another keeps its number: it is never reused, and it is listed below · the owner's request of 2026-10-24, 05:52 to 05:57 UTC
- 2026-10-24 · D-0013, D-0017, D-0021 · folded into D-0012 (runbook steps), D-0016 rule 1 (`docs/research/`) and D-0019 rule 4 (linter settings), with their rules, reasons, considered options and revisit conditions; the files are removed · the same request
- 2026-10-24 · D-0003 rule 2 · a new family, or a change to a row (its home, who numbers it, or closing the family), is made by its own record, whose PR updates the row in D-0003; D-0003 is no longer superseded for it · the same request
- 2026-10-24 · D-0004 rule 5 · for a decision number, the tombstone is a line in the numbers list below, because the decisions index is generated (D-0001 "Index") · follows D-0003 rule 6 above
- 2026-10-24 · D-0010 rule 4 · the three replaced Research drafts no longer need a header line naming what replaced them · the owner's request of 2026-10-24, 05:52 to 05:57 UTC, for no retire or replace notes
- 2026-10-24 · D-0015 · the rename scope is explicit batch citations with an old code, and its proof is 0 such citations · the owner's choice on the 2026-10-23 04:34 UTC decision card
- 2026-10-24 · D-0007, evidence 0007 · the reason for the PRD is the owner's yes to the 2026-10-19 decision card for a one-page PRD and frozen specs; the project brief is named as the coordinator agent's · the brief was agent-written, and the owner asked on 2026-10-24 that premises be checked
- 2026-10-24 · PRD goal 1 · start with one cluster in the home lab on Proxmox; one rented VPS joins it as an outside worker; cloud sites later · follows the owner's 2026-10-22 answer on the VPS's role
- 2026-10-24 · PRD goal 6 · everything is controllable from this repo; one-time console steps at the start are fine · follows the owner's 2026-10-14 statement on click-ops
- 2026-10-24 · D-0002 · the context, diagram and deployment target start with the home-lab cluster, as PRD goal 1 · follows the 2026-10-22 answer above
- 2026-10-24 · D-0011 · the "no click-ops" driver and its context read as PRD goal 6: controllable from this repo, one-time console steps at the start, and each job done by hand first (D-0012); the `hosts/` decision is unchanged · follows the 2026-10-14 statement above
- 2026-10-24 · D-0012 · a `manual` runbook may cover any job done by hand; the CKA scope applies to Kubernetes jobs · follows the owner's 2026-10-19 02:43 UTC request for a manual runbook first for each job, then an automated one

## Folded and reused numbers

These numbers have no file and no row in the index. They are never used again (D-0003 rule 6, D-0004).

- D-0006 (reused) · first used by the PR #9 draft, a full restatement of D-0005, closed unmerged on 2026-10-16; the owner approved the reuse under D-0004 on 2026-10-16 at 08:25 UTC. The current D-0006 was accepted with PR #10: approved 2026-10-16T08:28:58Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNTJTUNZbcPsUxG7TCKiX23s), head 0ae0493; merged as 0517ccf
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

- 2026-10-24 · STD-0002 · place numbers, the kept-empty block and the spare rows removed, and the home LAN range moved out of the public file, per the owner's request of 2026-10-24 05:51 and 05:56 UTC; first names replaced with "the owner" · PR #42
- 2026-10-24 · D-0003 · the family registry and rules brought to the current text from D-0009, D-0014, D-0015, D-0018 and D-0020; status back to accepted · PR #42
- 2026-10-24 · D-0009, D-0014, D-0015, D-0018, D-0020 · restated rules and supersede links removed; each keeps the family or rule change it adds, with its prefix check; all accepted · PR #42
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
- 2026-10-24 · D-0003 · the 2026-10-12 clash finding lists `SR` as it was measured · PR #42
- 2026-10-24 · D-0006, D-0014 · sentences that narrated earlier wording removed · PR #42
- 2026-10-24 · D-0001 to D-0020, STD-0001, decisions and standards READMEs, runbooks README · the owner named by role, not by first name, in the text and in `decision-makers` (D-0016 rule 5) · PR #42
- 2026-10-24 · D-0003 to D-0020, STD-0001 · `merged` names the merge commit, and `check` no longer refers to the removed quote · PR #42
- 2026-10-24 · D-0012, standards README, decisions README · D-0016 added to D-0012's related records; the `STD-` family cited at D-0003 rule 1; the index says where folded numbers are listed · PR #42
- 2026-10-24 · D-0010 · blank lines added around two option headings (Markdown style) · PR #42
