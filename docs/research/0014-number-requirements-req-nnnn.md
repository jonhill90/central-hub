---
record: D-0014
batch: RB-0072
researched: 2026-10-23
method: history of the requirements register in git and in the chat archive; inventory of the ID schemes in use; review of requirement-ID practice in requirements tools, standards and large projects; a count of the references a change would touch; an independent check
checks: an independent check re-read 9 ledger rows; 7 held, the reference count was corrected (it had counted lines, not occurrences) and one source was found to support less than claimed, so that rule was relabelled as the batch's own design; known-item recall was 3 of 8 cited directly and 8 of 8 counting the two earlier ID batches it builds on
---

# Evidence for D-0014: numbering requirements REQ-NNNN

This file summarises the research behind D-0014. It adds nothing that the research did not find. Each finding below traces to a row in the batch ledger.

## Question

Which ID format should requirements use, and how should agent-made ID schemes be checked?

## Findings

1. **The format in use was made by an agent.** It first appears in the register's baseline commit, written by an agent coordinator before this project existed. No message from the owner proposes or chooses the format; the owner's messages about it answer the wording of single rows. (Measured from git history and the chat archive; that an agent wrote it is inferred from them.)
2. **The format was never compared with alternatives.** The research behind D-0003 kept it because it did not clash, and a later register study treated the ID as a given. (From the earlier batches and the records.)
3. **The format does not match the house style.** D-0009's own driver says decisions are written `D-0007`, with a dash and four digits; the requirement format has no dash and two digits (from D-0009).
4. **The prefix clashes outside the project.** NIST SP 800-53 uses the same two letters for its Supply Chain Risk Management control family, for example `SR-3` [1]. Under D-0003 rule 2, the prefix would also block any future prefix that starts with those letters (inferred).
5. **Requirements tools use a short prefix and a number.** Doorstop's IDs are a document prefix, an optional separator and digits (`SRD002`) [2, 3]. sphinx-needs gives each type a prefix and checks IDs against a pattern [4].
6. **Some projects put type or place in the ID, and one rejected it.** Azure Verified Modules encode scope and type (`SFR`, `SNFR`) [5]. RTEMS uses component paths and puts the project name in every ID, and it rejected advice to put the requirement type in the ID [6, 7].
7. **Citing from outside.** OWASP ASVS asks other documents to cite its IDs with the version, because IDs can change between versions [8]. Chromium prefers public links and allows private tracker IDs only in commit footers [9].
8. **The cost of a change grows.** On 2026-10-23, requirement IDs occurred about 4,700 times across the Research repo, the project files and central-hub, and the count was growing (measured).
9. **Two live names cause confusion.** Keeping a second ID beside the current one means two names for one requirement, the confusion D-0003's research measured when one label had 7 meanings (inferred, from D-0003's evidence).
10. **The batch's first draft recommended keeping the format in use** and writing it down, and named `REQ-0001` style as the alternative if house style and a clean prefix weigh more (from the synthesis).

## How the decision used it

(Written from the record, not from the batch.)

D-0014 does not keep the agent-made format, because of findings 1 to 4. It chooses `REQ-NNNN` to match the house style (finding 3), keeps type and topic out of the number as D-0003 rule 7 does (finding 6), and writes the ID the same way in every live file during Foundation instead of keeping a second name, because of findings 8 and 9. It records the agent's first draft, keeping the format (finding 10), as option 3, which the owner did not choose.

## Limits

- ISO/IEC/IEEE 29148 is paywalled and was not read; the INCOSE guide was seen only in a search excerpt.
- NIST SP 800-53 was reached through a third-party catalogue page, not NIST's own site.
- Doorstop's command-line page returned 404, so its flags come from the document reference page.
- ID schemes in linters and policy engines were not searched.

## References

Relied on (the decision depends on these):

1. NIST SP 800-53 Rev. 5, control SR-3, through a third-party catalogue. <https://www.stigviewer.com/controls/nist-800-53/SR-3>
2. Doorstop, document reference. <https://doorstop.readthedocs.io/en/latest/reference/document.html>
3. Doorstop, README. <https://github.com/doorstop-dev/doorstop/blob/develop/README.md>
4. sphinx-needs, configuration. <https://sphinx-needs.readthedocs.io/en/latest/configuration.html>
5. Azure Verified Modules, Terraform resource module specification. <https://azure.github.io/Azure-Verified-Modules/specs/tf/res/>
6. RTEMS, "Requirements for requirements". <https://docs.rtems.org/docs/6.2/eng/req/req-for-req.html>
7. RTEMS developer list, July 2019. <https://lists.rtems.org/pipermail/devel/2019-July/054448.html>
8. OWASP Application Security Verification Standard. <https://asvs.owasp.org/>
9. Chromium, issue tracking guidelines. <https://www.chromium.org/issue-tracking/googler-guidelines/>

Background (read, not relied on):

10. INCOSE, Guide for Writing Requirements, webinar slides (search excerpt only). <https://www.incose.org/wp-content/uploads/2026/01/webinar_144_the_incose_gfwr_raising_the_ante.pdf>

All fetched 2026-10-23, except item 10.

## Working files

The register history, the ID inventory, the reference counts, the ledger and the corrections log are kept in the owner's private research archive as batch RB-0072. They are not needed to read this file.
