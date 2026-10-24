---
record: D-0007
batch: RB-0057
researched: 2026-10-18 to 2026-10-19
method: four source strands (standards, papers, labs and frameworks, practitioner canon) and a second round that read the items the first round missed; a known-item recall check; a devil's advocate pass; an independent claim check; a fit check against the project's accepted rules
checks: recall of 194 of 220 known items (88.2%), after a first round that found 76 of 223 and failed; an independent check of 150 claims, with 140 supported, 7 partly supported, 0 not supported and 3 unreachable; the check's 27 fixes applied
---

# Evidence for D-0007: a one-page PRD and frozen per-change specs

This file summarises the research behind D-0007. It adds nothing that the research did not find. Each finding below traces to the batch's synthesis, its strand files or its fit check.

## Question

What document set should Central Hub use in version 1 for "what to build and why" and "what changes", what happens to those documents after a change merges, and how do they avoid copying code?

## Findings

1. **Sources split on one question: what happens to a document after the work merges.** The batch grouped the 44 options its strands found into five shapes (inferred grouping; every option keeps its source's name): a living document kept current, such as Spec Kit's "Living Spec" and OpenSpec [1, 2]; a frozen record per change, such as Python PEPs, Kubernetes KEPs and Spec Kit's "Flow-Forward" [1, 3, 4]; a throw-away working plan [5]; the checks as the spec, as in Specification by Example [6]; and no separate document, where the PR or issue description is the record, as in GitLab and BMAD [16, 8].
2. **In practice, specs behave as frozen records.** In a study of 266 repositories, 81.5% of spec files had one commit and 98.3% had one author. Even OpenSpec's "living" capability specs had one commit in 47.4% of cases [9].
3. **Measured gains come from short context and checks, not longer documents.** Rules compiled into checks raised compliance from 67.0% to 88.3% [10]. Curated skills helped by 16.6 points, while self-generated ones hurt by 8 to 11.5 points [11]. Across 88,052 pull requests, specs in PRs showed no measured effect, though there "spec" mostly meant a link to a ticket (97.5%) and the output of spec tools was not tested [12].
4. **No study of a project-level PRD was found**, for either people or agents (measured: no strand found one). BMAD says a PRD is needed when more than one person must agree, and otherwise to skip it [8].
5. **Pointing to code instead of copying it is old standard advice.** IEEE 830-1998 says the same requirement "should not appear in more than one place" [13]. arc42 says never to copy code into documentation [14], and GitLab's handbook says to cross-link instead of repeating content [7].
6. **Two layers at most.** Nielsen Norman Group reports that more than two levels of progressive disclosure typically have low usability [15]. Applying that interface rule to documents is an analogy (inferred).
7. **Frozen records carry one risk.** Agents can read an old record as current intent [9]. A status field lets a merged spec say it is history without being moved (from the project's own layout notes, read in the fit check).
8. **Shape B fits the accepted rules.** One main branch with short-lived branches (D-0002) and acceptance by a message naming the PR number and head SHA (D-0001) suit a spec written on the change's branch and recorded by the merge (inferred, fit check). Three unaccepted in-house drafts already existed, so a new PRD should replace the PRD draft rather than sit beside it (inferred).
9. **Status words in the sources.** PEP 1 uses Draft, Active, Accepted, Provisional, Deferred, Rejected, Withdrawn, Final and Superseded [3]. KEPs use provisional, implementable, implemented, deferred, rejected, withdrawn and replaced [4]. The batch left the choice of words open.
10. **Checks need code.** central-hub had no code files when the batch ran (measured), so nothing could run executable acceptance checks in version 1.

## How the decision used it

(Written from the record, not from the batch.)

D-0007 chooses a frozen spec per change plus a one-page PRD (option 2) because of findings 1, 2 and 8. Its rule against copying code follows finding 5, and its two-layer limit follows finding 6. It keeps the PRD on the owner's answer to the 2026-10-19 decision card rather than as something the evidence requires (findings 3 and 4), and it defers executable checks because of finding 10. Its status field follows finding 7, and the choice of status words (finding 9) was left to D-0010.

## Limits

- Models from one vendor wrote every strand, the check and the devil's advocate, and that vendor publishes some of the sources.
- Six joint ISO/IEC/IEEE standards, among them 29148 and 15289, were read only as free previews; BABOK and the INCOSE guide came through secondary sources.
- Most of the evidence is practice advice. The measured studies are small, use one model, or are run by the author of the tool they test.
- 16 low- or medium-priority known items were not read.

## References

Relied on (the decision depends on these):

1. GitHub Spec Kit, "Spec persistence". <https://raw.githubusercontent.com/github/spec-kit/c6a4c18f1d01a8bec241c618eb6dfea952508744/docs/concepts/spec-persistence.md>
2. OpenSpec, concepts. <https://raw.githubusercontent.com/Fission-AI/OpenSpec/c794978f4f8845ce59693373c9dd882ee776588c/docs/concepts.md>
3. Python PEP 1. <https://peps.python.org/pep-0001/>
4. Kubernetes enhancements, KEP process. <https://raw.githubusercontent.com/kubernetes/enhancements/5b503a75369bdfdd494a2c2c72107a41bf6dd1a8/keps/sig-architecture/0000-kep-process/README.md>
5. M. Pocock, skills, "to-spec". <https://raw.githubusercontent.com/mattpocock/skills/49dd158d1076134a641b33efb035946536778336/docs/engineering/to-spec.md>
6. M. Fowler, "Specification by Example". <https://martinfowler.com/bliki/SpecificationByExample.html>
7. GitLab handbook, "Handbook usage", Single Source of Truth. <https://handbook.gitlab.com/handbook/about/handbook-usage/>
8. BMAD Method, "Choose a planning path". <https://raw.githubusercontent.com/bmad-code-org/BMAD-METHOD/61e01f82644c4bb533750cfa0d6d61ab61d2cc9b/docs/plan/choose-a-planning-path.md>
9. Agarwal et al., "Spec-Driven Development as Prescribed and as Practiced", 2026. <https://arxiv.org/abs/2608.25202>
10. ContextCov, instruction files compiled into checks, 2026. <https://arxiv.org/abs/2603.00822v2>
11. Li et al., "SkillsBench", 2026. <https://arxiv.org/abs/2602.12670>
12. ESEM 2026, study of 88,052 pull requests. <https://drops.dagstuhl.de/storage/00lipics/lipics-vol394-esem2026/LIPIcs.ESEM.2026.84/LIPIcs.ESEM.2026.84.pdf>
13. IEEE 830-1998, section 4.3.7, university-hosted copy. <https://people.eecs.ku.edu/~hossein/Teaching/Stds/0830.pdf>
14. arc42 FAQ, F-3. <https://faq.arc42.org/questions/F-3/>
15. Nielsen Norman Group, "Progressive disclosure". <https://www.nngroup.com/articles/progressive-disclosure/>
16. GitLab handbook, "Product development flow". <https://handbook.gitlab.com/handbook/product-development/how-we-work/product-development-flow/>

Background (read, not relied on): the batch listed 294 sources already held in the owner's corpus, and its strands read many more; they are listed in the private working files.

All fetched 2026-10-18 or 2026-10-19.

## Working files

The four strands, the second round, the recall check, the devil's advocate, the claim check, the fit check and the ledger are kept in the owner's private research archive as batch RB-0057. They are not needed to read this file.
