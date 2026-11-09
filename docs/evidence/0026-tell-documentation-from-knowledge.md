---
record: D-0026
batch: RB-0095 (knowledge layout), with RB-0069 (docs kinds) as already summarised for D-0012
researched: 2026-10-22 to 2026-11-03
method: review of published organizing methods and vendor guidance for agent-read stores; a findability test of six layouts with fresh agents, three runs each; reuse of the RB-0069 survey of 18 repositories with docs folders; on 2026-11-03, a read-only audit of every organization note in the research archive
checks: an independent check of RB-0095 passed with fixes (an unfair baseline was rerun with its register); the 2026-11-03 audit opened 90 of 103 organization notes in full or in part and listed the rest as skipped
---

# Evidence for D-0026: tell documentation from knowledge

This file summarises the research behind D-0026, and it adds nothing the research did not find.

## Question

Should a repository keep its documentation and its knowledge in one store or two? And what keeps an agent from mixing them up?

## Findings

1. **Docs folders sort by kind of document.** Of the 18 repositories read that have docs, 12 give decisions, proposals, runbooks or postmortems a folder of their own. Only 2 use reader-need folders at the top (RB-0069, measured; see [0012-sort-docs-by-kind-of-document.md](0012-sort-docs-by-kind-of-document.md)).
2. **Learning material was kept out of docs/.** Before this record, D-0012 rule 6 sent learning material to the research archive (sourced, D-0012).
3. **A written rule placed files better than folder shape did.** Every layout tested let fresh agents answer 23 or 24 of 24 questions. When the root README stated the placement rule in one sentence, placement was right in all 18 runs. Naming the register in the root README cut tool calls from 10 to 7 (RB-0095, measured).
4. **Finished work is seldom moved into an archive.** It is mostly deleted, with git history kept as the archive (RB-0095, from repository mining, measured).
5. **Hand-kept hub pages went stale.** In the owner's earlier notes system, the hand-kept maps of content stopped being updated (RB-0097, measured; the 2026-11-03 audit).

## Limits

- No published source sets the folders of a knowledge store inside a code repository. The notebook's layout comes from the owner's own method, the organization standard, and is not tested by outside research.
- The move from `docs/knowledge/` to the agent notebook rests on the owner's message of 2026-11-09 at 00:29 UTC, not on new research.
- The findability test ran on this project's own content, at its current size.
