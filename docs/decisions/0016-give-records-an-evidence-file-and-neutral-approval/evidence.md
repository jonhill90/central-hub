---
record: D-0016
batch: DE1
researched: 2026-10-23
method: survey of this repository's decision records; rapid review of published decision-record guidance and open-source decision processes; claim ledger; independent check
checks: known-item recall 17 of 20 (85%); an independent reviewing agent opened 26 of the 33 first ledger rows (23 supported, 3 partly, 0 not supported, 0 unreachable) and listed 14 fixes, all applied before the record was written
---

# Evidence for D-0016: evidence files and neutral approval

This file summarises the research behind D-0016. It adds nothing that the research did not find. Each finding below traces to a row in the batch ledger.

## Question

How should this public repository carry the research behind its decision records, and how should the owner's approval and reasons be recorded without quoting the owner?

## Findings

1. **Today's research pointers cannot be followed in public.** 13 of the 14 records point to research in a private repository or in project files. An outside request for the private repository returns "not found". Only one record (D-0005) lists public source addresses. (Measured on `main` at 05a48ff.)
2. **The owner is quoted throughout.** 13 of 14 record bodies quote the owner, and all 14 `accepted-evidence` blocks hold a `quote:` field with the owner's words. Every record also carries a chat message id. (Measured.)
3. **The research cannot be copied in as it is.** Every research folder the records cite quotes the owner, and the folders hold about 4.2 MB of Markdown. Each one contains public source addresses (11 to 859 unique, counted by search, not curated reference lists), so a public summary can be built from what exists. (Measured.)
4. **No process read quotes the approver.** Of 9 processes read, the 6 that describe how approval is recorded use a date, a role or handle, or a link: AWS adds "a timestamp, version, and list of stakeholders" [3]; Python's PEP 1 adds a Resolution header "with a direct link to the relevant post making a decision" [6]; the Rust RFC header links the RFC pull request [7]; Kubernetes KEPs list `approvers` by handle [9]; the UK government framework lists "stakeholders consulted" [4]; ecADR records the agreement as narrative [5]. MADR, Nygard and Azure Well-Architected carry only a status or roles [1, 2, 10]. (Inferred from their texts.)
5. **Published guidance asks for neutral, factual records that stand alone.** Nygard: the context section's language "is value-neutral. It is simply describing facts" [2]. Azure Well-Architected: "Keep records pithy, assertive, on-topic, and factual", and extra material may be linked "but the decision must be clear and stand alone without that material" [10].
6. **Evidence has a named place in the templates.** MADR's "More Information" section is where to "provide additional evidence/confidence for the decision outcome" [1]. The Rust RFC template has a "Prior art" section that includes papers [7]. PEP 1's Rationale should give "evidence of consensus" and discuss objections [6]. RFC 7322 says reference lists "must indicate whether each reference is normative or informative" [11].
7. **Companion files exist, but rarely.** PEP 1 lets support files sit in a subdirectory named for the PEP, meant for "auxiliary files such as diagrams" [6]. Each Kubernetes KEP is a folder holding the proposal and its metadata [9]. 3 of the 646 entries in the Rust RFC text folder are companion folders. RFC 3392's folder holds a "Rationale and alternatives" file linked from the RFC [8]. (Measured on public clones.)

## How the decision used it

(Written from the record, not from the batch.)


Findings 1 to 3 rule out keeping private links and copying the folders. Findings 4 and 5 set the neutral wording and the approval fields. Findings 6 and 7 set the evidence file's shape and the split into "relied on" and "background".

## Limits

- ISO/IEC/IEEE 42010:2022 was not read (paywalled).
- One search for papers found studies of why architecture decisions are made and how ADRs are adopted. None covers where evidence is stored, and none was read.
- Three pages (Nygard, the UK government framework, ecADR) were read through a summarising fetch tool, not as raw text.
- Records-management practice (provenance, finding aids) was not searched.

## References

Relied on (the decision depends on these):

1. MADR 4.0.0, ADR template. <https://raw.githubusercontent.com/adr/madr/4.0.0/template/adr-template.md>
2. M. Nygard, "Documenting Architecture Decisions", 2011. <https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
3. AWS Prescriptive Guidance, "ADR process". <https://docs.aws.amazon.com/prescriptive-guidance/latest/architectural-decision-records/adr-process.html>
4. UK Government, "Architectural decision record framework". <https://www.gov.uk/government/publications/architectural-decision-record-framework/architectural-decision-record-framework>
5. O. Zimmermann, "A Definition of Done for Architectural Decision Making" (ecADR), 2020. <https://ozimmer.ch/practices/2020/05/22/ADDefinitionOfDone.html>
6. Python PEP 1, "PEP Purpose and Guidelines". <https://raw.githubusercontent.com/python/peps/main/peps/pep-0001.rst>
7. Rust RFC template. <https://raw.githubusercontent.com/rust-lang/rfcs/master/0000-template.md>
8. Rust RFC 3392, "Leadership Council", and its companion folder. <https://raw.githubusercontent.com/rust-lang/rfcs/master/text/3392-leadership-council.md>
9. Kubernetes KEP template, `kep.yaml` and README. <https://raw.githubusercontent.com/kubernetes/enhancements/master/keps/NNNN-kep-template/kep.yaml>, <https://raw.githubusercontent.com/kubernetes/enhancements/master/keps/NNNN-kep-template/README.md>
10. Microsoft, Azure Well-Architected, "Maintain an architecture decision record". <https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record>
11. IETF RFC 7322, "RFC Style Guide". <https://www.rfc-editor.org/rfc/rfc7322.txt>

No background-only sources: every source read is used by a finding.

All fetched 2026-10-23.

## Working files

The full ledger (40 claims), the record survey, the recall check and the two independent checks are kept in the owner's private research archive as batch DE1. They are not needed to read this file.
