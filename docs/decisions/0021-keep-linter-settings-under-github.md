---
id: D-0021
title: Keep the docs linter settings under .github/, not in the repository root
status: accepted
date: 2026-10-24
decision-makers: [jon]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0008, D-0019]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-24T06:21:57Z
  approved-commit: c62cf9982508e3fc8e5a338f98fc8b87dfe92bf2
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNAqUPkvQ7d3ptmgAjUaDB92
  approval-names: "PR #41 and head c62cf99"
  check: the drafting agent read the message in the project thread at 2026-10-24T06:21Z; it names PR jonhill90/central-hub#41 and head c62cf99 itself. An independent check by a reviewing agent is still to do.
  merged: not yet; the owner merges PR #41, which carries this evidence commit on top of the approved commit
amends: [D-0019]
legacy-id: []
revisit-when: a docs tool cannot take a settings path; an editor or CI service that the owner uses needs the settings in the root; or D-0008's rule for the root changes
---

# Keep the docs linter settings under .github/, not in the repository root

## Context and Problem Statement

D-0019 rule 4 put the docs linter settings "as dotfiles in the repository root". The build added two: `.markdownlint.jsonc` (check 3) and `.vale.ini` (check 4).

D-0008 already says the root holds only what a reader needs before going deeper (README, AGENTS, SECURITY). The two dotfiles are neither entry points nor agent rules, so D-0019 rule 4 went against that pattern.

On 2026-10-24 the owner said the two root files look disorganized and do not follow the repository's patterns. On 2026-10-24 at 05:32 UTC the owner chose, on a decision card, to move both under `.github/`. That choice is not acceptance; this record still needs acceptance under D-0001.

## Decision Drivers

- **Keep the root short** (D-0008).
- **Checks give the same results** after the move.
- **Same command everywhere** (D-0019 rule 1). Local runs and CI keep using `run.sh`.

## Considered Options

1. **Move both settings files under `.github/`** and pass their paths with `--config` (this record).
2. **Keep them in the root**, where the tools and editor plugins find them without a flag.

## Decision Outcome

Chosen option: **1**.

1. markdownlint's settings move to `.github/docs-check/markdownlint.jsonc`. Vale's settings move to `.github/vale/vale.ini`, beside its rules.
2. `.github/docs-check/run.sh` passes each file with `--config`. markdownlint-cli2 takes `--config` as its base settings, and Vale takes `--config` as the path to its settings file. Vale reads `StylesPath` relative to that file.
3. `.github/.markdownlint.jsonc` stays. It extends the moved file and keeps the one exception for the PR template.
4. No docs-check settings file goes in the repository root.

This changes D-0019 rule 4 only. Its last clause, "linter settings as dotfiles in the repository root", reads in effect "linter settings under `.github/`, passed to each tool by `run.sh`". D-0019's exit path "the root dotfiles" reads in effect "the two settings files". D-0019's `amended-by` becomes `[D-0021]`, and its body stays as it is.

### Consequences

- Good: the root holds only README, AGENTS, CLAUDE, SECURITY and `.gitignore` again.
- Good: everything the docs checks need is under `.github/`, so dropping them is one folder and one workflow.
- Bad: an editor plugin for markdownlint or Vale no longer finds the settings by itself. It needs its settings path set once. `.github/docs-check/README.md` says so.
- Bad: running a tool directly, without `run.sh`, needs the `--config` flag.

### Confirmation

- `run.sh` gives the same results before and after the move on the same files. On a copy of `main` 33518e0, all four checks pass and the word report lists the same 6 findings.
- Long lines stay allowed, which shows the moved markdownlint settings are applied. The PR template's exception still holds.
- No `.markdownlint*` or `.vale.ini` file is in the repository root.

## Pros and Cons of the Options

### 2. Keep them in the root

- Good: tools and editor plugins find them without a flag.
- Bad: two settings files in a root that D-0008 keeps for entry points.

## More Information

- **Evidence:** no research batch of its own. The tool behaviour was measured in the drafting thread on 2026-10-24: `markdownlint-cli2 --help` lists `--config` as "the path to a configuration file to define the base configuration", and `vale --help` lists `--config` as a file path to a `.vale.ini`. Both checks were then run with the moved files. Tool background is in D-0019's evidence file, [../research/0019-check-docs-on-every-pr.md](../research/0019-check-docs-on-every-pr.md).
- **Exit path:** move the two files back to the root and drop the `--config` flags. A new record supersedes this one.
- **Related records:** D-0008 (short root), D-0019 (the checks).
