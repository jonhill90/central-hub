---
record: D-0015
batch: RB-0074
researched: 2026-10-23
method: a scripted inventory of every research spec title in the project files and the Research repo; a review of how other registries number studies, proposals and drafts; a count of the citations a rename would touch; an independent check
checks: the inventory is complete by construction (75 of 75 folders with a code in their spec title); an independent check confirmed all 75 inventory rows, found a third copy of one batch and two codes used as aliases, and corrected one source's wording, all applied
---

# Evidence for D-0015: numbering research batches RB-NNNN

This file summarises the research behind D-0015. It adds nothing that the research did not find. Each finding below traces to a row in the batch ledger.

## Question

How should research batches be identified, given that each thread made up its own code?

## Findings

1. **The codes have no rule.** 75 research folders carry a batch code in 9 different shapes, and no file defines how a code is made. The spec template only says "(batch <ID>)". (Measured.)
2. **Some codes clash.** 3 codes name two different batches each: `RR1`, `AT1` and `VN1`. Two batches sit under different folder names in the two stores. (Measured.)
3. **Some codes look like other labels.** `SR1` looks like the old `SR` requirement IDs, and `K1` and `V1` already had several meanings in D-0003's research (measured).
4. **Registries hand out a plain number and keep the name beside it.** Python PEPs take the next free number at the draft stage, checked by the editors [1]. Kubernetes KEPs take their tracking issue number, and their folders pair it with a short name (seen in the page's links, not stated as a rule) [2]. IETF drafts carry a descriptive name until an RFC number comes on publication [3], and ClinicalTrials.gov assigns an NCT number at registration [4]. The common pattern is one registry, a plain number given at registration, and a readable name next to it (inferred).
5. **The clashing codes cannot be renamed by script.** `RR1`, `AT1` and `VN1` are cited about 280 times in the Research repo and the project files, and each citation has to be read in context. Every other code renames mechanically. (Measured.)
6. **The counter-argument.** A lighter option is to borrow a number that already exists, as KEPs do, instead of adding a registered family (from the independent check).

## How the decision used it

(Written from the record, not from the batch.)

D-0015 gives research batches one registered family, `RB-NNNN`, because of findings 1 to 3. It numbers a batch when its spec is written, from one register with the folder name kept as the readable name, because of finding 4. Its rename rule says the clashing codes are read in context, because of finding 5. It rejects citing folder paths because folder names already differ between the two stores (finding 2).

## Limits

- The IETF and ClinicalTrials.gov pages did not load; those findings rest on search excerpts.
- No papers, labs or skills category was searched, because batch numbering is project practice.
- Folders whose spec title has no batch code were not counted.

## References

Relied on (the decision depends on these):

1. Python PEP 1. <https://peps.python.org/pep-0001/>
2. Kubernetes enhancements, KEPs README. <https://github.com/kubernetes/enhancements/blob/master/keps/README.md>
3. IETF, "Naming your Internet-Draft" (search excerpt only). <https://authors.ietf.org/naming-your-internet-draft>
4. ACCC glossary, NCT number (search excerpt only). <https://acori-glossary.accc-cancer.org/definition/national-clinical-trial-(nct)-number>

All fetched 2026-10-23, except where marked as a search excerpt.

## Working files

The inventory of every batch code, the ledger and the corrections log are kept in the owner's private research archive as batch RB-0074. They are not needed to read this file.
