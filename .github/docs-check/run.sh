#!/usr/bin/env bash
# Run the docs checks (D-0019 rule 1). CI runs the same commands.
# Usage: .github/docs-check/run.sh [front-matter|links|markdown|words|all]   (default: all)
# Needs: python3 with requirements.txt installed; lychee 0.24.2 on PATH, or LYCHEE=/path/to/lychee;
# for markdown, `npm ci --prefix .github/docs-check`; for words, Vale 3.25.1 on PATH, or VALE=/path/to/vale.
# DOCS_BASE is the commit to compare with (default: where this branch left origin/main).
set -euo pipefail
cd "$(dirname "$0")/../.."
here=.github/docs-check

front_matter() {
  python3 "$here/check_docs.py" .
  bash "$here/tests/test_check_docs.sh"
}

links() {
  # Links inside the repo only, with #anchors. Outside links are a weekly report, never a gate.
  "${LYCHEE:-lychee}" --offline --include-fragments --no-progress './**/*.md'
}

changed_md() {
  # Markdown files this branch adds or changes. Records and evidence files are frozen, so they
  # count only in the PR that adds them (D-0019 rule 3).
  local base=${DOCS_BASE:-$(git merge-base origin/main HEAD)}
  { git diff --name-only --diff-filter=ACMR "$base" HEAD -- '*.md' ':!docs/decisions/0*' ':!docs/research/0*'
    git diff --name-only --diff-filter=A "$base" HEAD -- 'docs/decisions/0*.md' 'docs/research/0*.md'; } | sort -u
}

markdown() {
  local files
  files=$(changed_md)
  if [ -z "$files" ]; then echo "markdown: no Markdown files changed"; return 0; fi
  # shellcheck disable=SC2086
  "$here/node_modules/.bin/markdownlint-cli2" $files
}

words() {
  local vale=${VALE:-vale}
  # The generated Vale files match the glossary (D-0019 rule 5).
  python3 "$here/gen_vale_terms.py" .
  if [ -n "$(git status --porcelain -- .github/vale)" ]; then
    git status --porcelain -- .github/vale
    echo "words: .github/vale differs from docs/glossary.md; run $here/gen_vale_terms.py and commit the result" >&2
    return 1
  fi
  # Report only: every rule on every document. Findings never fail the run.
  "$vale" --no-exit --output line docs AGENTS.md README.md SECURITY.md
  # Gate: the owner-quote rule (D-0016 rule 5) on changed files, except the approval template.
  local files
  files=$(changed_md | grep -v -x 'docs/specs/README.md' || true)
  if [ -z "$files" ]; then echo "words: no Markdown files changed"; return 0; fi
  # shellcheck disable=SC2086
  "$vale" --output line --filter='.Name=="CentralHub.OwnerWords"' $files
}

case "${1:-all}" in
  front-matter) front_matter ;;
  links) links ;;
  markdown) markdown ;;
  words) words ;;
  all) front_matter; links; markdown; words ;;
  *) echo "usage: $0 [front-matter|links|markdown|words|all]" >&2; exit 2 ;;
esac
