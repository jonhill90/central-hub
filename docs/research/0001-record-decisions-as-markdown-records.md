---
record: D-0001
batch: RB-0001
researched: 2026-10-10
method: rapid review of published decision-record guidance and tooling; repository mining of 16 public repositories pinned to commit SHAs; two designs written independently by two agents and compared
checks: all 16 repository sources were fetched again, with 15 rows fully confirmed, 1 partly confirmed and 0 errors; both independent designs kept unedited and every disagreement listed
---

# Evidence for D-0001: recording decisions as Markdown records

This file summarises the research behind D-0001. It adds nothing that the research did not find. Each finding below traces to the batch's synthesis, its practice review or its repository table.

## Question

How should central-hub record decisions and keep an index of them, so the index covers every decision, including ones not yet decided, and every part can be replaced later without losing data?

## Findings

1. **The records are the log.** No source read prescribes a separate index file: adr.github.io says the collection of records "constitute its decision log" [2], AWS says the collection "creates the decision log" [4], and Azure Well-Architected calls the record "an append-only log" [5]. In practice, 15 of the 16 repositories read keep an index file next to the records; Backstage uses a site sidebar instead [11].
2. **The index sits beside the records.** `docs/adr/` is the most common folder; `docs/decisions/` is used by MADR itself, chromedp and TechSpokes [11].
3. **Undecided items are records.** In the repositories read, decisions under consideration appear in the index as records marked Proposed (or Open in chromedp). None keeps unwritten questions in a separate file. TechSpokes sends open questions to issues, and chromedp sends ideas to Discussions [11].
4. **Shared statuses.** Proposed, accepted and superseded appear across the sources; most also have deprecated and rejected. AWS and Azure Well-Architected treat an accepted record as immutable [1, 4, 5].
5. **Index tools are thin.** About half the repositories write their index by hand; 6 generate it. No maintained off-the-shelf tool validating records was found: MADR runs markdownlint only, adr-tools' table of contents lists titles without status, adr-log's last release was 2020-10-21, and the repositories that validate wrote their own checks [3, 8, 9, 11].
6. **No source covers this owner's case.** No source read covers a single owner whose agents act under the owner's own account (inferred from their silence).
7. **The two independent designs agreed on the core.** Both proposed plain Markdown records with flat front matter in git, a permanent ID per decision, a generated index with a drift check, and that nothing an agent can write counts as acceptance. They disagreed on six points (where unwritten questions live, how acceptance is proved, location, file naming, revision snapshots and the dependency field), and the synthesis lists and resolves each one.

## How the decision used it

(Written from the record, not from the batch.)

D-0001 chooses one Markdown file per decision in `docs/decisions/`, with a generated index, because of findings 1 to 3; log4brains is named as a possible reader [10]. Its statuses follow finding 4, as described by the government guidance read [6, 7]. It accepts writing a small generator and validator because of finding 5, and it ties acceptance to the Foundation phases because of finding 6.

## Limits

- 9 of the 16 repositories are small repositories from 2026, so they show current practice more than long-established convention.
- Last-commit dates were not seen for any GitHub repository, because the API refused the requests; release dates come from release pages and package registries.
- Generated sites were fetched separately, and their deployed commit was not verified.
- One repository row (log4brains) was only partly confirmed on re-fetch: its rendered site was not checked.

## References

Relied on (the decision depends on these):

1. M. Nygard, "Documenting Architecture Decisions", 2011. <https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
2. adr.github.io, home page. <https://adr.github.io/>
3. MADR 4.0.0 and its template. <https://adr.github.io/madr/>, <https://raw.githubusercontent.com/adr/madr/main/template/adr-template.md>
4. AWS Prescriptive Guidance, "ADR process". <https://docs.aws.amazon.com/prescriptive-guidance/latest/architectural-decision-records/adr-process.html>
5. Microsoft, Azure Well-Architected, "Maintain an architecture decision record". <https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record>
6. UK government, "Architectural decision record framework". <https://www.gov.uk/government/publications/architectural-decision-record-framework/architectural-decision-record-framework>
7. UK GDS Way, "Documenting architecture decisions". <https://gds-way.digital.cabinet-office.gov.uk/standards/architecture-decisions.html>
8. adr-tools, `generate toc` source. <https://raw.githubusercontent.com/npryce/adr-tools/master/src/_adr_generate_toc>
9. adr-log, README. <https://raw.githubusercontent.com/adr/adr-log/master/README.md>
10. log4brains. <https://github.com/thomvaill/log4brains>
11. The 16 repositories read, each at a pinned commit:
    - <https://github.com/backstage/backstage/blob/b8a841f2c04f902fc2d6fde7d0bc7e02243bd2af/microsite/sidebars.ts>
    - <https://github.com/microsoft/agent-governance-toolkit/blob/c767f8333f413bd1a93e82836b7aa226280b61ae/docs/adr/index.md>
    - <https://github.com/aws-solutions-library-samples/global-capacity-orchestrator-on-aws/blob/b994f7dbe901217a1ec3d44c706e8496db41b854/docs/adr/README.md>
    - <https://github.com/aws-samples/sample-portable-app-deploy-on-aws/blob/8f72b3c760fcc2dc97fe6f719e6f335213a21522/docs/architecture-decision-records/README.md>
    - <https://github.com/redhat-et/zero-trust-agent-demo/blob/53e708ec13114065f98d92a198df9dcd2bd2f07a/docs/adr/README.md>
    - <https://github.com/thomvaill/log4brains/blob/17e32021a8c5130386f17e921d4efa6da7709a66/docs/adr/index.md>
    - <https://github.com/adr/madr/blob/ba75bb1b20d42af5746b246ad348c202419ae681/docs/decisions/index.md>
    - <https://github.com/adr/adr-log/blob/47cb22a953261f6e5f447c87d40e10a88f03b2df/docs/adr/index.md>
    - <https://github.com/chromedp/chromedp/blob/dddfecf01d55a7848d9c79622cb22060c9b847bd/docs/decisions/README.md>
    - <https://github.com/daronyondem/agent-cockpit/blob/597520128782c67d8d2d29eab8164743a3abe5ae/docs/adr/README.md>
    - <https://github.com/CapTrix/openfoundry/blob/090e3f19b6b90fb77c23d779a318957c937067b2/docs/architecture/adr/README.md>
    - <https://github.com/IsmaelMartinez/teams-for-linux/blob/89882ce6ed1a1250589e4a84d7d4876639cdf251/docs-site/docs/development/adr/README.md>
    - <https://github.com/oaknational/oak-open-curriculum-ecosystem/blob/2a77738377a45164e7d7c2459b8c2874591d7e18/docs/architecture/architectural-decisions/README.md>
    - <https://github.com/FRACerqueira/adrpy-tui/blob/fde25e563bbe7fac0426b47f23795c8eaf4b99df/doc/adr/INDEX.md>
    - <https://github.com/What-We-Will/community-platform/blob/b1653d0eda4f1e5585b5b71a9d56a81a9a60516a/docs/adr/README.md>
    - <https://github.com/TechSpokes/skill-github-repositories-coordination/blob/f42a30abbd2b6472e27b33788d24feaae3f0d91a/docs/decisions/README.md>

Background (read, not relied on):

12. ThoughtWorks Technology Radar, "Lightweight Architecture Decision Records". <https://www.thoughtworks.com/radar/techniques/lightweight-architecture-decision-records>
13. adr.github.io, "AD practices" and "ADR templates". <https://adr.github.io/ad-practices/>, <https://adr.github.io/adr-templates/>
14. adr.github.io, "ADR tooling". <https://adr.github.io/adr-tooling/>
15. Backstage ADR plugin, README. <https://raw.githubusercontent.com/backstage/community-plugins/main/workspaces/adr/plugins/adr/README.md>

All fetched 2026-10-10.

## Working files

The practice review, the repository table and both independent designs are kept in the owner's private research archive as batch RB-0001. They are not needed to read this file.
