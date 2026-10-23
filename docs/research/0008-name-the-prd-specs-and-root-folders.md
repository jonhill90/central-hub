---
record: D-0008
batch: RB-0036, with the names question kept in RB-0057's folder
researched: 2026-10-17
method: review of the owner's earlier layout research; scoping review of repository standards and template tools (22 source families); repository mining of 28 repositories' move history; a devil's advocate pass; a live placement test with fresh agents
checks: "an independent agent re-checked a seeded random sample of about 22% of the claims in each strand, plus named must-check claims: 94 of 104 passed, 9 were partly right and 1 failed, and the standards strand's 8 were fixed; every move count it re-ran on fresh clones matched"
---

# Evidence for D-0008: the names of the PRD, the specs folder and the root folders

This file summarises the research behind D-0008. It adds nothing that the research did not find. Each finding below traces to the batch's synthesis, its strand files or its independent check.

## Question

What common layout should the owner's repositories start from, so a repository can grow without a reorganisation, and what does central-hub look like under it?

## Findings

1. **Standards agree only on hygiene files.** Across 22 source families, only LICENSE (5), README (4) and `.github/workflows/` (4) are named by 4 or more. `docs/` reaches 4 only by counting places where it is an allowed location, and no code folder reaches 4 [1, 2, 3, 4].
2. **Roots named for a tool that was swapped churned most.** onedr0p/home-ops made 1,812 cross-root file moves and onedr0p/cluster-template renamed its template folder 5 times [5, 6]. A stable `kubernetes/` root stopped churning once settled: its cross-root moves fell from 986 in 2023 to 1 in 2026 [5]. (Measured.)
3. **Empty folders made in advance did not absorb growth.** Day-one placeholder folders in the owner's own repositories were renamed, split or deleted; growth was absorbed by stable names for what each part does (measured).
4. **One placement rule gave one answer.** In a live test with fresh agents, the rule "by artifact and who runs it" placed all 6 cases the same way, and all 6 runs put the VPS rebuild script in `hosts/` (measured; small sample, not blind-graded).
5. **The names themselves were not found in a source.** The batch proposed `private-network/`, `hosts/`, `kubernetes/`, `dns/` and `backup/`, and the later names question proposed `docs/PRD.md` and `docs/specs/`. These were the drafting agent's proposals built from findings 1 to 4, not names a source chose (from the record's own context and the names question).
6. **Counter-evidence on where the PRD sits.** One of the owner's earlier repositories and two of the owner's templates kept the PRD and spec at the root, treating them as inputs to the work rather than documentation of it (from the names question).

## How the decision used it

(Written from the record, not from the batch.)

D-0008 keeps the root short and puts the PRD under `docs/` (option 1), weighing finding 1 against the counter-evidence in finding 6. Its rule that root folders are named for their job, with `kubernetes/` as a stated exception, follows finding 2. Its rule that a folder is created with its first real file follows finding 3. It says openly that the names were proposals rather than findings (finding 5).

## Limits

- The repository table could not use the GitHub API, so external pull request and issue pages were read by a fetching tool.
- The stop rule for repository mining was not strictly met; 28 repositories were read against a minimum of 15.
- Some details of one template tool came from model knowledge and were not fetched; the decision does not depend on them.
- Move counts are exact-match file moves only, so they undercount moves that also edited the file.

## References

Relied on (the decision depends on these):

1. GitHub Docs, "Creating a default community health file". <https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file>
2. GitHub Docs, "About READMEs". <https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes>
3. OpenSSF Scorecard, checks. <https://github.com/ossf/scorecard/blob/main/docs/checks.md>
4. golang-standards, project layout. <https://github.com/golang-standards/project-layout>
5. onedr0p/home-ops, history to commit 3e7c113b53ea. <https://github.com/onedr0p/home-ops>
6. onedr0p/cluster-template, history to commit 2afa02558c9f. <https://github.com/onedr0p/cluster-template>

Background (read, not relied on):

7. Backstage, software templates. <https://backstage.io/docs/features/software-templates/>
8. copier, updating a project. <https://copier.readthedocs.io/en/stable/updating/>
9. CNCF Platforms White Paper. <https://tag-app-delivery.cncf.io/whitepapers/platforms/>
10. Go, "Organizing a Go module". <https://go.dev/doc/modules/layout>

All fetched 2026-10-17.

## Working files

The prior-work review, the standards review, the evolution table with commit SHAs, the devil's advocate, the placement tests, the independent check and the names question are kept in the owner's private research archive as batch RB-0036 and in batch RB-0057's folder. They are not needed to read this file.
