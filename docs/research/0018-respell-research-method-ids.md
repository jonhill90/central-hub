---
record: D-0018
batch: RB-0075
researched: 2026-10-23
method: repository mining of the methods catalogue, its scripts and its citations; reading of four published catalogues; claim ledger; independent check
checks: an independent check re-counted the uses in the Research repo, sampled 55 ID uses from 55 files and compared 557 method-table rows with the catalogue; its corrections and the dependencies it found are in the ledger
---

# Evidence for D-0018: research method IDs

This file summarises the research behind D-0018. It adds nothing that the research did not find. Each finding below traces to a row in the batch ledger.

## Question

Research methods are cited as `RM01` to `RM122`. Should that agent-made scheme stay, be respelled or be replaced, and how should it fit the ID family registry?

## Findings

1. **The catalogue has 122 methods,** `RM01` to `RM122`, and 40 more are proposed (measured).
2. **The number is the method's place in the list.** Three scripts give a new method the ID `RM` plus the list length plus one, so rebuilding or re-sorting the list would renumber methods (measured). The build script reads the catalogue from a copy on one machine, not from the Research repo (measured).
3. **The IDs are used heavily but only inside the project:** about 6,400 times in the Research repo and 4,300 times in the project files, and not at all in central-hub (measured).
4. **Every number checked means one method.** A sample of 55 uses from 55 files, and 557 method-table rows, all name the catalogue's method for that number (measured). So a script can rename them.
5. **The research gate depends on the shape.** The gate template names method IDs (sourced), and the hook that checks new specs matches `RM` followed by digits in three files (measured). The hook runs from a setup script that is pasted by hand (measured). Four more scripts assume the `RMnn` shape when they read or build IDs (measured).
6. **The published catalogues read tend to keep an entry's number** (inferred from the sources below; NIST's retirement rules were not read, and one ATT&CK reuse is possible [6]). MITRE ATT&CK marks retired entries deprecated or revoked, and a revoked one points to its replacement [1]. ATT&CK versions the catalogue as a whole [2]. NIST SP 800-53 numbers controls by family prefix, number and enhancement, such as `SA-15(13)` [3]. CWE keeps deprecated entries under their number with a pointer to the replacement (search summary only) [5].
7. **Position-based IDs change.** OWASP ASVS numbers requirements by chapter, section and position, and because "the identifiers may change between versions", it asks others to cite them with the version [4] (sourced).

## How the decision used it

(Written from the record, not from the batch.)

D-0018 stores each method's number instead of working it out from the list (findings 2, 6 and 7), keeps retired methods with a pointer (finding 6), and respells the IDs by script (finding 4). It sends the setup-script change to the owner in the same step as the rename (finding 5).

## Limits

- CWE's pages returned an error, so finding 6's CWE part rests on search summaries [5].
- NIST's rules for withdrawn controls were not read.
- An ATT&CK reuse of one retired tactic ID was seen only in a search summary and not confirmed [6].
- The other catalogues in the project (about 8 ID shapes in 10 catalogues) were listed but not studied.

## References

Relied on (the decision depends on these):

1. MITRE ATT&CK Python library, "MITRE ATT&CK Data" (revoked and deprecated objects). <https://mitreattack-python.readthedocs.io/en/latest/mitre_attack_data/mitre_attack_data.html>
2. MITRE ATT&CK, "Versions of ATT&CK". <https://attack.mitre.org/resources/versions/>
3. NIST, SP 800-53 Rev. 5 Update 1. <https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final>
4. OWASP, Application Security Verification Standard. <https://asvs.owasp.org/>

Background (read, not relied on):

5. MITRE CWE, deprecated entries: search summary only, for the query "CWE deprecated entries ID never reused"; cwe.mitre.org returned HTTP 503 when fetched.
6. Elastic, "Remap detection rules to MITRE ATT&CK" (search summary only). <https://www.elastic.co/docs/solutions/security/detect-and-alert/remap-mitre-attack>

Items 1 to 3 fetched during the batch (2026-10-23); item 4 fetched the same day by batch RB-0072.

## Working files

The full ledger (26 claims), the recall check and the independent check are kept in the owner's private research archive as batch RB-0075. They are not needed to read this file.
