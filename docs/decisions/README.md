<!-- Generated from each record's front matter. Do not edit by hand. -->
# Decision log

Each decision is one record in this folder. Records are written one at a time, in the order Jon picks, and only `proposed` records come from agents. Decisions not yet picked stay in the decision map, a backlog kept in the project files outside this repo.

| ID | Title | Status | Waits on | Date |
|---|---|---|---|---|
| D-0001 | [Record decisions as one Markdown file each, with a generated index](0001-record-decisions-as-markdown-records.md) | accepted | — | 2026-10-11 |
| D-0002 | [Use one main branch, environments as folders, and type-named short-lived branches](0002-use-one-main-branch-with-environment-folders.md) | accepted | D-0001 | 2026-10-11 |
| D-0003 | [Use a few registered global ID families; write every other label with its file name](0003-use-registered-id-families-and-file-qualified-labels.md) | superseded | D-0001 | 2026-10-12 |
| D-0004 | [During Foundation, allow a void ID's number to be reused, with the owner's approval and a tombstone](0004-allow-reuse-of-void-ids-during-foundation.md) | accepted | D-0003 | 2026-10-13 |
| D-0005 | [Measure all of Central Hub against six industry pillars plus two labelled Central Hub pillars](0005-measure-central-hub-against-eight-pillars.md) | accepted | D-0001 | 2026-10-16 |
| D-0006 | [Correct an accepted record in place when the decision does not change](0006-allow-corrections-to-accepted-records.md) | accepted | D-0001 | 2026-10-16 |
| D-0007 | [Use a one-page PRD and frozen per-change specs as version 1 of Central Hub's requirement records](0007-use-a-one-page-prd-and-frozen-per-change-specs.md) | accepted | D-0001, D-0003 | 2026-10-19 |
| D-0008 | [Name the PRD docs/PRD.md, keep specs in docs/specs/, and name root folders by job](0008-name-the-prd-specs-and-root-folders.md) | accepted | D-0001, D-0007 | 2026-10-19 |
| D-0009 | [Add a STD- family for standards to the ID family registry](0009-add-a-standards-id-family.md) | accepted | D-0001, D-0003 | 2026-10-22 |
| D-0010 | [Give specs five status words and retire the three October 2026 drafts](0010-set-spec-status-words-and-retire-old-drafts.md) | accepted | D-0001, D-0007, D-0008 | 2026-10-22 |
| D-0011 | [Keep the code for every machine below Kubernetes in hosts/, one subfolder per vendor product, with Terraform modules in their own repository](0011-keep-machine-code-in-hosts.md) | accepted | D-0001, D-0008 | 2026-10-22 |
| D-0012 | [Sort docs/ by kind of document, add runbooks, architecture, glossary, postmortems and diagrams with their first file, and keep plans and playbooks out](0012-sort-docs-by-kind-of-document.md) | proposed | D-0001, D-0007, D-0008, D-0009, D-0010 | 2026-10-23 |
