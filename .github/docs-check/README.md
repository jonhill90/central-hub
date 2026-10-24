# Docs checks

The checks D-0019 decides. This folder holds check 1 (front matter) and the command that also runs check 2 (links inside the repo) and check 3 (Markdown style). Check 4 arrives in a later PR.

| Path | What it is |
|---|---|
| `run.sh` | The one command. `run.sh front-matter`, `run.sh links`, `run.sh markdown`, or no argument for all three. CI runs the same command. |
| `check_docs.py` | Check 1: reads each record's front matter as YAML 1.2, checks it against its kind's schema, then checks the rules that cross files. |
| `schemas/` | One JSON Schema 2020-12 file per kind of document, plus `common.schema.json`. |
| `tests/test_check_docs.sh` | Test cases: each breaks a good record one way and expects check 1 to fail. |
| `requirements.txt` | Python packages for check 1, pinned with hashes. |
| `package.json`, `package-lock.json` | markdownlint-cli2 for check 3, pinned by the lockfile. Its settings are in `/.markdownlint.jsonc`, and `.github/.markdownlint.jsonc` adds one exception for the PR template. |

## Run it locally

```sh
python3 -m venv .venv && .venv/bin/pip install --require-hashes -r .github/docs-check/requirements.txt
npm ci --prefix .github/docs-check
PATH=".venv/bin:$PATH" LYCHEE=/path/to/lychee .github/docs-check/run.sh
```

lychee 0.24.2 comes from its releases page; the workflow checks the file's SHA-256.

The Markdown check lints only the files your branch adds or changes, compared with `origin/main` (set `DOCS_BASE` to compare with another commit). An existing decision record or evidence file is skipped, because those change only by correction (D-0019 rule 3).

A PR that changes this folder or `.github/workflows/docs.yml` says so in its title (D-0019 rule 9).
