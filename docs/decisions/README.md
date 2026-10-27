<!-- Generated from each record's front matter. Do not edit by hand. -->
# Decision log

Each decision is one record in this folder. Records are written one at a time, in the order the owner picks, and only `proposed` records come from agents. Decisions not yet picked stay in the backlog, kept in the project files outside this repo, with their options in the decision map. A correction or a decision change to an accepted record is made in place and listed in [CORRECTIONS.md](CORRECTIONS.md) (D-0006). A number with no row here was folded into another record and is free for the next new record; CORRECTIONS.md says which.

| ID | Title | Status | Waits on | Date |
|---|---|---|---|---|
| D-0001 | [Record decisions as one Markdown file each, with a generated index](0001-record-decisions-as-markdown-records.md) | accepted | — | 2026-10-11 |
| D-0002 | [Use one main branch, environments as folders, and type-named short-lived branches](0002-use-one-main-branch-with-environment-folders.md) | accepted | D-0001 | 2026-10-11 |
| D-0003 | [Use a few registered global ID families; write every other label with its file name](0003-use-registered-id-families-and-file-qualified-labels.md) | accepted | D-0001 | 2026-10-12 |
| D-0004 | [During Foundation, allow a void or folded ID's number to be reused, with the owner's approval and a tombstone](0004-allow-reuse-of-void-ids-during-foundation.md) | accepted | D-0003 | 2026-10-13 |
| D-0005 | [Measure all of Central Hub against six industry pillars plus two labelled Central Hub pillars](0005-measure-central-hub-against-eight-pillars.md) | accepted | D-0001 | 2026-10-16 |
| D-0006 | [Edit accepted records in place](0006-allow-corrections-to-accepted-records.md) | accepted | D-0001 | 2026-10-16 |
| D-0007 | [Use a one-page PRD and frozen per-change specs as version 1 of Central Hub's requirement records](0007-use-a-one-page-prd-and-frozen-per-change-specs.md) | accepted | D-0001, D-0003 | 2026-10-19 |
| D-0008 | [Name the PRD docs/PRD.md, keep specs in docs/specs/, and name root folders by job](0008-name-the-prd-specs-and-root-folders.md) | accepted | D-0001, D-0007 | 2026-10-19 |
| D-0009 | [Add a STD- family for standards to the ID family registry](0009-add-a-standards-id-family.md) | accepted | D-0001, D-0003 | 2026-10-22 |
| D-0010 | [Give specs five status words](0010-set-spec-status-words.md) | accepted | D-0001, D-0007, D-0008 | 2026-10-22 |
| D-0011 | [Keep the code for every machine below Kubernetes in hosts/, one subfolder per vendor product, and no Terraform modules of its own until code is reused](0011-keep-machine-code-in-hosts.md) | accepted | D-0001, D-0008 | 2026-10-22 |
| D-0012 | [Sort docs/ by kind of document, add runbooks, architecture, glossary, postmortems and diagrams with their first file, and keep plans and playbooks out](0012-sort-docs-by-kind-of-document.md) | accepted | D-0001, D-0007, D-0008, D-0009, D-0010 | 2026-10-23 |
| D-0013 | [Keep central-hub public, and name each exception to best practice with what keeps it secure](0013-keep-central-hub-public.md) | proposed | D-0001 | 2026-10-26 |
| D-0014 | [Number requirements REQ-NNNN](0014-number-requirements-req-nnnn.md) | accepted | D-0001, D-0003, D-0004, D-0006 | 2026-10-23 |
| D-0015 | [Number research batches RB-NNNN](0015-number-research-batches-rb-nnnn.md) | accepted | D-0001, D-0003, D-0006 | 2026-10-23 |
| D-0016 | [Give each decision record a public evidence file, and record the owner's approval and reasons in neutral words](0016-give-records-an-evidence-file-and-neutral-approval.md) | accepted | D-0001, D-0006 | 2026-10-23 |
| D-0018 | [Number research methods RM-NNNN](0018-number-research-methods-rm-nnnn.md) | accepted | D-0001, D-0003, D-0006, D-0016 | 2026-10-23 |
| D-0019 | [Check the docs on every PR, with front matter and inside links as gates, Markdown style on changed files, and word checks built from the glossary](0019-check-docs-on-every-pr.md) | accepted | D-0001, D-0012, D-0016 | 2026-10-23 |
| D-0020 | [Number backlog items BL-NNNN](0020-number-backlog-items-bl-nnnn.md) | accepted | D-0001, D-0003, D-0006, D-0016 | 2026-10-24 |
| D-0023 | [Use Argo CD with its web UI as the GitOps engine on c1, installed from the pinned upstream manifest with no git credential](0023-use-argo-cd-as-the-gitops-engine.md) | proposed | D-0001, D-0002, D-0011 | 2026-10-27 |
