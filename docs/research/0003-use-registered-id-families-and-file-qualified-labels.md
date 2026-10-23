---
record: D-0003
batch: RB-0003
researched: 2026-10-12
method: inventory of every ID family in the owner's files; rapid review of persistent-identifier and document-numbering practice; repository mining of 18 outside projects at commit SHAs; one independent design with a contrarian case
checks: every claim labelled fetched, search summary or memory; after network access opened, every search-summary source was fetched and checked (21 confirmed, 6 corrected in wording or attribution, 6 still unfetched); 18 repositories, against a minimum of 10; the independent design kept unedited and every disagreement listed
---

# Evidence for D-0003: registered ID families and file-qualified labels

This file summarises the research behind D-0003. It adds nothing that the research did not find. Each finding below traces to the batch's synthesis, its practice review, its repository table or its inventory.

## Question

What ID scheme should the owner's files and central-hub use, so a label points at exactly one thing, parallel agents never hand out the same number, and the owner can read and say the IDs?

## Findings

1. **The labels in use clash.** The owner's files held about 75 ID families, and about 50 of them restart at 1 in each document. 21 labels clash: `P1` alone has 7 meanings, two of them in one file, and "ADR 0001" names 3 different records. Every clash uses a one-letter prefix; no prefix of two or more letters clashed. (Measured.)
2. **Practice agrees on the lifecycle rules.** Never reuse or delete an ID, supersede rather than edit, leave a tombstone when withdrawing, keep old IDs resolving after a merge, register prefixes so they stop clashes, and keep meaning out of the number [1, 2, 3, 4, 5, 6, 7, 8]. Requirements tools agree: IBM DOORS never reuses a purged object number [15, 16].
3. **Collisions happen where the author mints the number.** In the 18 projects read, nobody renumbers. Collisions appear only where the author picks the next number, as with adr-tools' highest-plus-one numbering [11] and a duplicate number in Kotlin's KEEP. Projects that number late or have one minter (Rust RFCs, PEPs, Backstage) avoid them [14].
4. **The sturdiest schemes keep identity apart from meaning.** StrictDoc keeps a human ID beside a machine ID, and doorstop keeps the ID apart from the item's level in the document [14].
5. **Opaque IDs suit machines, not readers.** ARK and DOI policy prefer opaque identifiers, and UUID guidance says to treat UUIDs "as opaquely as possible" [1, 9, 12]; time-based IDs such as ULIDs, UUIDv7 and timestamps avoid collisions [9, 13] but cannot be read or said (inferred); a Crossref community thread argues that opaque DOIs cause harm in practice [10]. The batch weighed this and kept readable family prefixes, with opaque IDs allowed underneath as machine aliases.
6. **Project acronyms in prefixes are discouraged.** The ARK draft says "using an acronym representing a project or a department is discouraged" [1].
7. **An older proposal fits practice but misses two rules.** An earlier unaccepted documentation draft (`platform:ADR-0001`) matched the lifecycle rules, but had no rule for parallel minting and no registry, and it built the parent into the ID, so an ID breaks when its item moves. (Read from the draft.)

## How the decision used it

(Written from the record, not from the batch.)

D-0003 chooses a few registered global families and file-qualified local labels (option 1) because of findings 1 and 3. Its rules on numbering late with one owner, never reusing and keeping meaning out of the number follow findings 2 to 4. It rejects opaque IDs as the IDs the owner reads (finding 5), avoids project acronyms (finding 6), and rejects the older namespaced draft (finding 7).

## Limits

- Several primary sites were first blocked by the network policy; most were fetched later, but 6 sources were never fetched, among them ISO/IEC/IEEE 29148 (paywalled) and go-fair.org (refused).
- The inventory skipped captured third-party copies, JSON files and IDs that existed only in chat.
- Raw GitHub practice files were read at their default branch head with no commit recorded, because the API was refused.
- The cost estimates for each option come from the independent design and were not measured.

## References

Relied on (the decision depends on these):

1. ARK Identifier Scheme, Internet-Draft. <https://datatracker.ietf.org/doc/html/draft-kunze-ark>
2. Python PEP 1. <https://raw.githubusercontent.com/python/peps/main/peps/pep-0001.rst>
3. M. Nygard, "Documenting Architecture Decisions", 2011. <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
4. McMurry et al., PLOS Biology, 2017 (identifier design lessons). <https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.2001414>
5. OBO Foundry, ID policy. <https://raw.githubusercontent.com/OBOFoundry/OBOFoundry.github.io/master/id-policy.md>
6. DataCite, tombstone pages. <https://support.datacite.org/docs/tombstone-pages>
7. Rust RFCs, README. <https://raw.githubusercontent.com/rust-lang/rfcs/master/README.md>
8. W3C, "Cool URIs don't change". <https://www.w3.org/Provider/Style/URI>
9. RFC 9562, Universally Unique IDentifiers. <https://www.rfc-editor.org/rfc/rfc9562.txt>
10. Crossref community, "Opaque DOIs considered harmful". <https://community.crossref.org/t/opaque-dois-considered-harmful/13788/3>
11. adr-tools, `adr-new`. <https://raw.githubusercontent.com/npryce/adr-tools/master/src/adr-new>
12. DOI Handbook, numbering. <https://www-old.doi.org/doi_handbook/2_Numbering.html>
13. ULID specification. <https://raw.githubusercontent.com/ulid/spec/master/README.md>
14. The 18 projects read, each at a commit: python/peps (545c670f1e98), rust-lang/rfcs (d2705ad64ba4), kubernetes/enhancements (8659e382efab), golang/proposal (0be13090fdb0), ethereum/EIPs (d394152cc2ef), apple/swift-evolution (f4fa78fe9c8c), Kotlin/KEEP (c3485b0b420e), tc39/proposals (849adcde1775), npryce/adr-tools (b3279baf9be2), adr/madr (ba75bb1b20d4), thomvaill/log4brains (17e32021a8c5), joelparkerhenderson/architecture-decision-record (c15e7b1f8edf), doorstop-dev/doorstop (969c0af355a0), strictdoc-project/strictdoc (cc8be791316a), backstage/backstage (b8a841f2c04f), obsidianmd/obsidian-help (08ef563f07b7), zk-org/zk (4df5a5db2946), and the IETF RFC series at rfc-editor.org (web pages, no commit).
15. IBM DOORS community, purged object IDs. <https://community.ibm.com/community/user/discussion/is-there-any-way-to-reclaim-purgeddiscarded-object-ids>
16. IBM DOORS DXL reference, "Next Object Absolute Number". <https://jazz.net/dxl/html/376%20-%20Next%20Object%20Absolute%20Number.html>

Background (read, not relied on):

17. Cloud Posse, proposal to index ADRs by ISO 8601 date (rejected). <https://docs.cloudposse.com/resources/adrs/proposed/proposed-use-iso-8601-date-index-for-adrs/>
18. clan.lol, ADR numbering process. <https://clan.lol/docs/26.05/decisions/03-adr-numbering-process>
19. GO FAIR Foundation, principle F1. <https://www.gofair.foundation/f1>
20. RFC Editor, "Errata in RFCs". <https://www.rfc-editor.org/errata-definitions/>

All fetched 2026-10-12.

## Working files

The ID inventory with every clash by file and line, the practice review with its 62 sources, the repository table and the independent design are kept in the owner's private research archive as batch RB-0003. They are not needed to read this file.
