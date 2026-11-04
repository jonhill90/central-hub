---
record: D-0012
batch: RB-0069
researched: 2026-10-22
method: four source strands (standards, papers, repositories and agent skills, canon and vendor guidance); a sweep of the owner's earlier research; a known-item recall check; a devil's advocate pass; an independent claim check; the proposed map tested on 5 real items from the project
checks: recall of 51 of 55 known items (93%); an independent check sampled 123 of 268 ledger rows (46%), including every row the map relies on, with 116 confirmed, 7 partly confirmed and 0 wrong; the check's corrections applied
---

# Evidence for D-0012: sorting docs by kind of document

This file summarises the research behind D-0012. It adds nothing that the research did not find. Each finding below traces to the batch's synthesis, its ledger or its strand files.

## Question

Which kinds of documentation does central-hub need, which folders hold them, and what must a runbook and a postmortem contain?

## Findings

1. **No standard or paper names docs folders.** ISO/IEC/IEEE 15289 and ISO/IEC 20000-1 put layout out of their scope [1, 2], and no paper read tests a folder scheme (measured: an arXiv search for Diátaxis returned no papers).
2. **Real repositories give records their own folder.** 12 of the 18 repositories with docs give decisions, proposals, runbooks or postmortems a folder of their own, even where their guides are sorted another way. Only 2 of 18 use Diátaxis at the top of `docs/`, and none of the 20 keeps a plans folder [3]. (Measured.)
3. **Diátaxis does not ask for four top folders.** A page later removed from its repository says it is "not a scheme into which documentation must be placed - four boxes" [4].
4. **Some kinds are living and some are frozen.** NIST treats plans and procedures as kept current, and incident records as evidence whose integrity is preserved [5, 6].
5. **Runbooks have the strongest outcome evidence of any kind.** At one large company, incidents with a linked troubleshooting guide took about 13 hours to mitigate against about 19 hours without (correlational). The most common guide failures were missing content and examples (32%), broken links (13%) and wrong steps (11%) [7].
6. **Runbook content in the sources.** AWS's runbook template lists an ID, description, tools, permissions, author, last update, escalation contact and steps [8]. NIST SP 800-34 chapter 4 covers activation, assessment, stepwise recovery, escalation and validation, and asks for plans to be tested or exercised periodically [6]. No field appears in all 9 runbook templates read (measured).
7. **Postmortems.** Of 584 public incident reports, most give the cause and the fix but leave out how the incident was found [9]. One repository read requires every postmortem to link a procedure [10].
8. **Where readers look.** In 25 popular repositories, nested READMEs held about 19% of feature documentation and `docs/` folders about 3% [11].
9. **Names.** Every agent skill that names a decisions folder uses `docs/adr/`, while MADR uses `docs/decisions/` [12]. "Playbook" means different things at Google, AWS and incident tools, [13, 8], and the standard software engineering vocabulary has no entry for it (measured, standards strand).
10. **Architecture descriptions.** About half the repositories read keep architecture docs. matklad suggests one short file with an overview, a code map and invariants [14], and a 65-person study found that a structured format made no difference against an essay format [15].
11. **Public and private.** NIST SP 800-34 makes contact lists standard plan content and marks the plan sensitive [6], which conflicts with a public repository (inferred, devil's advocate).

## How the decision used it

(Written from the record, not from the batch.)

D-0012 sorts docs by kind of document (option 1) because of findings 1 to 3, and marks each folder living or frozen because of finding 4. It adds a README to each root folder on top, because of finding 8. Its runbook format draws on findings 5 and 6, its postmortem format on finding 7, and its single architecture file on finding 10. It keeps `docs/decisions/` and has no `plans/` or `playbooks/` folder because of findings 2 and 9. Its rule that runbooks name secret keys and never values follows finding 11. The fields and status words themselves are the drafting agent's proposal, accepted with the record, because no source agrees on them (finding 6).

## Limits

- Paywalled standards were read as previews; ISO/IEC/IEEE 15289's generic content clauses and 42010's annex were not read. No folder choice rests on them.
- One large public runbook repository could not be cloned, so its folder list comes from its README links.
- A few known items were not read, among them the Azure Well-Architected documentation guidance and Kruchten's 4+1 views.

## References

Relied on (the decision depends on these):

1. ISO/IEC/IEEE 15289, preview. <https://webstore.iec.ch/en/iec_catalog/product/preview/?id=cHViL3BkZi9wcmV2aWV3L2luZm9faXNvaWVjaWVlZTE1Mjg5e2VkNC4wfWVuLnBkZg==>
2. ISO/IEC 20000-1:2018, preview. <https://webstore.iec.ch/en/iec_catalog/product/preview/?id=cHViL3BkZi9wcmV2aWV3L2luZm9faXNvaWVjMjAwMDAtMXtlZDMuMH1lbi5wZGY=>
3. The 20 repositories read, each pinned to a commit, listed in the batch's repository table (among them kubernetes/website, fluxcd/flux2, backstage/backstage, cilium/cilium, argoproj/argo-cd and chezmoi-sh/atlas).
4. Diátaxis, removed page "complex hierarchies", recovered from the framework's git history. <https://github.com/evildmp/diataxis-documentation-framework>
5. NIST SP 800-61r3, incident response. <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-61r3.pdf>
6. NIST SP 800-34 Rev. 1, contingency planning. <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf>
7. Shetty et al., "AutoTSG: Learning and Synthesis for Incident Troubleshooting", ESEC/FSE 2022. <https://arxiv.org/abs/2205.13457>
8. AWS Well-Architected, OPS07-BP03, "Use runbooks to perform procedures". <https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/ops_ready_to_support_use_runbooks.html>
9. Sillito and Kutomi, "Failures and Fixes: A Study of Software System Incident Response", ICSME 2020. <https://arxiv.org/abs/2008.11192>
10. chezmoi-sh/atlas, `docs/incidents/README.md` at commit 293f1e0. <https://github.com/chezmoi-sh/atlas>
11. Puhlfürß, Montgomery and Maalej, "An Exploratory Study of Documentation Strategies for Product Features in Popular GitHub Projects", ICSME 2022. <https://arxiv.org/abs/2208.01317>
12. MADR 4.0.0. <https://adr.github.io/madr/>
13. Google SRE workbook, "On-call". <https://sre.google/workbook/on-call/>
14. matklad, "ARCHITECTURE.md", 2021. <https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html>
15. Ernst and Robillard, "A Study of Documentation for Software Architecture", EMSE 2023. <https://arxiv.org/abs/2305.17286>

Background (read, not relied on):

16. Diátaxis, "Start here". <https://diataxis.fr/start-here/>
17. Google SRE book, "Postmortem culture". <https://sre.google/sre-book/postmortem-culture/>
18. Atlassian, incident postmortems handbook. <https://www.atlassian.com/incident-management/handbook/postmortems>

All fetched 2026-10-22, except item 4, read from git history.

## Working files

The four strands, the prior-corpus sweep, the recall check, the devil's advocate, the claim check and the ledger are kept in the owner's private research archive as batch RB-0069. They are not needed to read this file.
