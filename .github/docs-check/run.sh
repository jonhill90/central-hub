#!/usr/bin/env bash
# Run the docs checks (D-0019 rule 1). CI runs the same commands.
# Usage: .github/docs-check/run.sh [front-matter|links|all]   (default: all)
# Needs: python3 with requirements.txt installed; lychee 0.24.2 on PATH, or LYCHEE=/path/to/lychee.
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

case "${1:-all}" in
  front-matter) front_matter ;;
  links) links ;;
  all) front_matter; links ;;
  *) echo "usage: $0 [front-matter|links|all]" >&2; exit 2 ;;
esac
