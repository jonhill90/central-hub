---
record: D-0019
batch: RB-0076
researched: 2026-10-23
method: scoping review of docs-checking tools; repository mining of six public docs repositories at pinned commits; every proposed tool run on this repository's main branch; a draft check script with test cases; claim ledger; independent check, recall check and contrarian pass
checks: an independent check sampled 37 of 50 source and measured ledger rows and found that the first draft script let repeated keys through, which was fixed and tested; a recall check found 38 of 41 known items after fixes
---

# Evidence for D-0019: check the docs on every PR

This file summarises the research behind D-0019. It adds nothing that the research did not find. Each finding below traces to a row in the batch ledger.

## Question

How should this repository test and lint its documents (front matter, Markdown, links and words) and run those checks on every PR, so that broken front matter cannot merge? Which methods, which placement and which words does that work need?

## Findings

1. **Nothing checks the docs today.** `.github/` holds only CODEOWNERS and the PR template (measured).
2. **Faults had reached `main`.** At 7915625 two files had front matter that was not valid YAML, D-0009 and the evidence file for D-0008, because a plain value contained ": ", which YAML 1.2.2 §7.3.3 forbids [1]. D-0012's `amended-by` missed D-0013 (measured). After the correction in PR #33 the draft check found 0 errors (measured).
3. **Front matter: a schema per kind, plus a script for rules across files.** MDN checks front matter with its own script against one JSON Schema [7], and GitLab checks one doc type's front matter with a schema [8] (measured in their repositories). The schema validators read (remark-lint-frontmatter-schema, check-jsonschema) check one file at a time, so no tool found checks an ID against its file name, two-way links, evidence pairing or index rows (inferred from [4] and [5]). JSON Schema's current version is 2020-12 [3] (sourced).
4. **The YAML loader matters.** The first draft script used a YAML 1.1 loader that kept the last of two repeated keys and read `yes` as true, so a repeated `status:` passed (measured). With a YAML 1.2 loader that rejects repeated keys, 10 of 10 test cases pass (measured). yamllint flags the same two faults [6] (sourced).
5. **Markdown style is noisy on old files.** markdownlint-cli2 with its defaults finds 1,328 issues in 39 files, 964 of them line length (measured). With line length, table style and the front-matter title rule turned off and `<br>` allowed, 194 remain, 169 of them in accepted records and evidence files, and 19 of the other 25 in the PR template (measured). MDN lints only the files a PR adds or changes [7] (measured).
6. **Links: inside links can gate, outside links cannot.** lychee offline with anchors checked 65 inside links and found 0 broken (measured). Online, 25 of 26 errors were HTTP 403 from one site refusing the sandbox, and 1 was a real 404 (measured). A docs-as-code talk advises not letting someone else's downtime block a build, and running a full check weekly [11] (sourced). MADR checks links on a monthly schedule as well as on PRs [9] (measured). About 10% of 9.6 million links in code comments were found dead [17] (sourced).
7. **Words: a glossary can drive the check.** Vale's vocabularies and its substitution check map a word to a preferred one [12] (sourced). Backstage runs Vale on changed files with an accept list [10], and GitLab maps words to preferred terms with a link to its word list [8] (measured). ISO 10241-1 gives terms a status of preferred, admitted or deprecated [15] (search summary only), and the Glossarist concept model carries the same three [14] (sourced). Google's word list marks entries avoid, use with caution or don't use [19] (sourced).
8. **Word findings on today's files are mostly in old records.** A term rule generated from a sample glossary found 79 uses of one unsettled word, and 78 were in records or generated files written before the word was settled (measured). A case-sensitive rule flagged "System" at the start of a sentence; making single lower-case words case-insensitive removed that false positive (measured). A rule for quoting the owner found 10 real lines and 2 false positives in the approval template in `docs/specs/README.md` (measured).
9. **CI safety.** GitHub advises pinning actions to a full commit SHA, a read-only token and avoiding `pull_request_target` [2] (sourced). MDN and Backstage pin actions to SHAs, and Backstage pins the Vale binary by checksum [7] [10] (measured).
10. **The checks are not an outside verifier.** A required status check makes all required checks pass before merge [13] (sourced), but a workflow in the same repository can be changed by the PR it checks (inferred). Requiring a workflow from another repository is a GitHub Enterprise Cloud feature [16] (sourced), so these checks do not meet Activation gate item 2 (inferred).
11. **Words for the work.** Lint comes from S. C. Johnson's 1978 program checker [18] (sourced). Verification is "confirmation, through the provision of objective evidence, that specified requirements have been fulfilled" (ISO 9000:2015 via NIST) [20], and validation confirms the requirements for a specific intended use [21] (sourced).

## How the decision used it

(Written from the record, not from the batch.)

D-0019 makes front matter a gate with a schema per kind and one script for cross-file rules (findings 2, 3 and 4). It gates inside links and reports outside links weekly (finding 6). It gates Markdown style only on files a PR adds or changes, so frozen records are not touched (finding 5). It generates the word rules from the glossary with ISO 10241-1 statuses, gates only the owner-quote rule and reports the rest (findings 7 and 8). The workflow rules follow finding 9, and Rule 9 and the Consequences state finding 10. The words table uses finding 11.

## Limits

- The workflow was written as a sketch and never run on GitHub; its pins are not filled in.
- github.com returned HTTP 403 to this environment for releases and some pages, so tool versions were taken from npm, crates.io and the Go module proxy.
- The IEEE/ISO SEVOCAB vocabulary timed out, so definitions come from NIST's copies of ISO 9000:2015. ISO 10241-1 and ISO 1087 were seen only in search summaries.
- No study of documentation linting itself was found; the papers cited are about dead links and documentation issues in general.
- The independent check chose its sample rather than drawing it at random.
- Whether GitHub shows a front-matter parse error on the page was not checked.

## References

Relied on (the decision depends on these):

1. YAML Language Development Team, "YAML Ain't Markup Language version 1.2.2", §7.3.3. <https://yaml.org/spec/1.2.2/>
2. GitHub Docs, "Secure use reference" (Actions). <https://docs.github.com/en/actions/reference/security/secure-use>
3. JSON Schema, "Specification" (2020-12). <https://json-schema.org/specification>
4. remark-lint-frontmatter-schema. <https://github.com/JulianCataldo/remark-lint-frontmatter-schema>
5. check-jsonschema, "Usage". <https://check-jsonschema.readthedocs.io/en/stable/usage.html>
6. yamllint, "Rules". <https://yamllint.readthedocs.io/en/stable/rules.html>
7. MDN content repository at 8557706: `front-matter-config.json`, `scripts/front-matter_linter.js`, `.github/workflows/pr-check-lint_content.yml`. <https://github.com/mdn/content>
8. GitLab repository at 38d5d46: `.vale.ini`, `doc/.vale/gitlab_base/SubstitutionWarning.yml`. <https://github.com/gitlabhq/gitlabhq>
9. MADR repository at ba75bb1: `.markdownlint.yml`, `.github/workflows/check-links.yaml`. <https://github.com/adr/madr>
10. Backstage repository at d723272: `.vale.ini`, `.github/workflows/verify_docs-quality.yml`. <https://github.com/backstage/backstage>
11. LWN, "Treating documentation as code" (FOSDEM 2024), 2024-02-26. <https://lwn.net/Articles/963037/>
12. Vale, "Vocabularies" and "Substitution". <https://docs.vale.sh/keys/vocabularies>, <https://docs.vale.sh/checks/substitution>
13. GitHub Docs, "Available rules for rulesets". <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>
14. Glossarist, concept model. <https://github.com/glossarist/concept-model>
15. ISO 10241-1, term statuses: search summary only, for the query "ISO 10241-1 preferred term admitted term deprecated term".
16. GitHub Changelog, "Requiring workflows with repository rules is generally available", 2023-10-11. <https://github.blog/changelog/2023-10-11-requiring-workflows-with-repository-rules-is-generally-available/>
17. H. Hata et al., "9.6 Million Links in Source Code Comments", ICSE 2019. <https://2019.icse-conferences.org/details/icse-2019-Technical-Papers/19/9-6-Million-Links-in-Source-Code-Comments-Purpose-Evolution-and-Decay>
18. S. C. Johnson, "Lint, a C Program Checker", Bell Labs, 1978.
19. Google, developer documentation style guide, "Word list". <https://developers.google.com/style/word-list>
20. NIST CSRC glossary, "verification". <https://csrc.nist.gov/glossary/term/verification>
21. NIST CSRC glossary, "validation". <https://csrc.nist.gov/glossary/term/validation>

Background (read, not relied on):

- markdownlint-cli2. <https://github.com/DavidAnson/markdownlint-cli2>
- lychee. <https://github.com/lycheeverse/lychee>
- pre-commit. <https://pre-commit.com/>
- CommonMark spec 0.31.2. <https://spec.commonmark.org/>
- GitHub Flavored Markdown spec. <https://github.github.com/gfm/>
- W3C, SKOS Reference. <https://www.w3.org/TR/skos-reference/>
- textlint. <https://textlint.org/>
- Write the Docs, "Docs as Code". <https://www.writethedocs.org/guide/docs-as-code/>
- Microsoft Writing Style Guide. <https://learn.microsoft.com/en-us/style-guide/welcome/>
- G. Aghajani et al., "Software Documentation Issues Unveiled", ICSE 2019, as summarised by Never Work in Theory. <https://neverworkintheory.org/2021/10/06/software-documentation-issues-unveiled.html>

All web items were fetched during the batch (2026-10-23) except item 15. Repository items were read from shallow clones at the commits named.

## Working files

The full ledger (71 claims), the measured tool outputs, the draft check script with its schemas and tests, the recall check and the independent check are kept in the owner's private research archive as batch RB-0076. They are not needed to read this file.
