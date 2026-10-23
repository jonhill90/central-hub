---
record: D-0006
batch: ADR-C1
researched: 2026-10-16
method: rapid review of published decision-record guidance and comparable record systems; claim ledger; independent quote check
checks: 21 of 21 quoted passages matched the fetched text; 6 claims found to go further than their sources were reworded before use
---

# Evidence for D-0006: correcting an accepted record

This file summarises the research behind D-0006. It adds nothing that the research did not find. Each finding below traces to a row in the batch ledger.

## Question

Does a fix that leaves a decision unchanged need a full superseding record, or may the accepted record be corrected in place?

## Findings

1. **Supersession is described for a changed decision.** Nygard keeps a reversed decision and marks it superseded [1]. Fowler applies "superseded" once a record is "significantly modified or replaced" [4]. No source read asks for a near-copy record to fix an error that leaves the decision the same (14 sources; inferred from their silence).
2. **Sources split on editing an accepted record.**
   - Never edit, supersede instead: AWS [2], Azure Well-Architected [3], Fowler [4].
   - Correct in place, supersede only a changed decision: UK GDS Way [5], the joelparkerhenderson collection [6]. Python's PEP 1 says resolved PEPs are "no longer substantially modified" [7], which implies minor edits are allowed (inferred).
   - List errors in a separate record: IETF RFC errors are tracked in an errata record with their own types and statuses [9].
3. **Tooling already links records in ways other than supersession.** adr-tools has a free-form link option besides supersede, and its own example labels one such link "Amends / Amended by" [8].
4. **The four-digit number is not a limit.** MADR assumes no more than 9,999 records [10], but the zero-padded format is a minimum width: formatting 10000 with `%04d` prints `10000` (measured).

## How the decision used it

D-0006 takes the middle position in finding 2 and the "amends" link in finding 3. It keeps the strict position as its exit path.

## Limits

- ISO/IEC/IEEE 42010:2022 was not read (paywalled).
- One empirical study (ICSA 2026) was read as an abstract only; a second (Buchgeher et al., IEEE Access 2023) was seen only as a search snippet [15].

## References

Relied on (the decision depends on these):

1. M. Nygard, "Documenting Architecture Decisions", 2011. <https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
2. AWS Prescriptive Guidance, "ADR process". <https://docs.aws.amazon.com/prescriptive-guidance/latest/architectural-decision-records/adr-process.html>
3. Microsoft, Azure Well-Architected, "Maintain an architecture decision record". <https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record>
4. M. Fowler, "Architecture Decision Record" (bliki). <https://martinfowler.com/bliki/ArchitectureDecisionRecord.html>
5. UK GDS Way, "Documenting architecture decisions". <https://gds-way.digital.cabinet-office.gov.uk/standards/architecture-decisions.html>
6. J. Parker Henderson, architecture-decision-record collection, README. <https://github.com/joelparkerhenderson/architecture-decision-record>
7. Python PEP 1, "PEP Maintenance". <https://peps.python.org/pep-0001/>
8. N. Pryce, adr-tools, `src/adr-new`. <https://raw.githubusercontent.com/npryce/adr-tools/master/src/adr-new>

Background (read, not relied on):

9. RFC Editor, errata search. <https://www.rfc-editor.org/errata.php>
10. MADR 4.0.0. <https://adr.github.io/madr/>
11. AWS Prescriptive Guidance, "ADR best practices". <https://docs.aws.amazon.com/prescriptive-guidance/latest/architectural-decision-records/best-practices.html>
12. ThoughtWorks Technology Radar, "Lightweight Architecture Decision Records". <https://www.thoughtworks.com/radar/techniques/lightweight-architecture-decision-records>
13. O. Zimmermann, "How to create Architectural Decision Records (ADRs) — and how not to", 2023. <https://ozimmer.ch/practices/2023/04/03/ADRCreation.html>
14. ICSA 2026 paper on ADRs in 921 GitHub repositories (abstract only). <https://conf.researchr.org/details/icsa-2026/icsa-2026-papers/34/>

15. G. Buchgeher et al., IEEE Access 11 (2023) 63725-63740, DOI 10.1109/ACCESS.2023.3287654 (search snippet only, not fetched).

Items 1 to 14 fetched 2026-10-16.

## Working files

The full ledger (27 claims) and the quote check are kept in the owner's private research archive as batch ADR-C1. They are not needed to read this file.
