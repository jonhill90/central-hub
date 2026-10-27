# Docs checks

The checks D-0019 decides. This folder holds check 1 (front matter), the index generator, the glossary generator for check 4 (words), and the one command that runs all four checks.

| Path | What it is |
|---|---|
| `run.sh` | The one command. `run.sh front-matter`, `run.sh links`, `run.sh markdown`, `run.sh words`, or no argument for all four. CI runs the same command. |
| `check_docs.py` | Check 1: reads each record's front matter as YAML 1.2, checks it against its kind's schema, then checks the rules that cross files. |
| `check_vlans.py` | Part of check 1: fails when the home VLAN file in `hosts/` differs from STD-0002's Home VLANs table in a VLAN ID, use or prefix. |
| `schemas/` | One JSON Schema 2020-12 file per kind of document, plus `common.schema.json`. |
| `tests/test_check_docs.sh` | Test cases: each breaks a good record one way and expects check 1 to fail. |
| `gen_index.py` | Writes the index tables in `docs/decisions/README.md` and `docs/standards/README.md` from each file's front matter (D-0001 "Index"). Check 1 fails if a committed table differs; run it and commit what it writes. |
| `gen_vale_terms.py` | Check 4: writes the Vale word list and term rule in `.github/vale/` from `docs/glossary.md`. CI fails if the committed files differ. |
| `requirements.txt` | Python packages for check 1, pinned with hashes. |
| `package.json`, `package-lock.json` | markdownlint-cli2 for check 3, pinned by the lockfile. |
| `markdownlint.jsonc` | Check 3's settings, passed with `--config` (D-0019 rule 4). `.github/.markdownlint.jsonc` extends it with one exception for the PR template. |

## Run it locally

```sh
python3 -m venv .venv && .venv/bin/pip install --require-hashes -r .github/docs-check/requirements.txt
npm ci --prefix .github/docs-check
PATH=".venv/bin:$PATH" LYCHEE=/path/to/lychee .github/docs-check/run.sh
```

lychee 0.24.2 and Vale 3.25.1 come from their releases pages; the workflow checks each file's SHA-256. Vale's settings are in `.github/vale/vale.ini`, passed with `--config` (D-0019 rule 4), and its rules sit beside it.

No settings file sits in the repository root (D-0008, D-0019 rule 4). An editor plugin for markdownlint or Vale needs its settings path pointed at these files.

The Markdown check lints only the files your branch adds or changes, compared with `origin/main` (set `DOCS_BASE` to compare with another commit). An existing decision record or evidence file is skipped, because those change only by correction (D-0019 rule 3).

The word check reports glossary findings on every document without failing. It fails only on two rules (both D-0016 rule 5): the owner-quote rule, in every Markdown file, and the owner-name rule, in files under `docs/` only (`AGENTS.md` and `CLAUDE.md` name the owner on purpose). Both gate every Markdown file your branch adds or changes, compared with `origin/main`, including edited decision records and evidence files; they skip only `docs/specs/README.md`, which holds the approval template. After you change `docs/glossary.md`, run `python3 .github/docs-check/gen_vale_terms.py` and commit what it writes.

A PR that changes this folder or `.github/workflows/docs.yml` says so in its title (D-0019 rule 9).
