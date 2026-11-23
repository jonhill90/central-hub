#!/usr/bin/env bash
# lead-time.py classes a PR as guarded the way the merge verdict does: by path, by a changed secret line, or by a fork head.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
python3 -I - "$here/../../speed/lead-time.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("lead", sys.argv[1]); lead = importlib.util.module_from_spec(spec); spec.loader.exec_module(lead)
full = "jonhill90/central-hub"
own = {"head": {"repo": {"full_name": full}}}
fork = {"head": {"repo": {"full_name": "someone/central-hub"}}}
plain = {"filename": "docs/runbooks/a.md", "patch": "@@ -1 +1 @@\n+a plain line"}
cases = [
    ("a plain docs change is plain", own, [plain], False),
    ("a changed secretKeyRef line is guarded", own, [{"filename": "hosts/kubernetes/apps/a/deploy.yaml", "patch": "@@ -1 +1 @@\n+  secretKeyRef:"}], True),
    ("a fork head is guarded", fork, [plain], True),
    ("a workflow path is guarded", own, [{"filename": ".github/workflows/x.yml", "patch": "@@ -1 +1 @@\n+x"}], True),
    ("a file with changes and no patch is guarded", own, [{"filename": "hosts/x.bin", "changes": 3}], True),
]
fails = 0
for name, pr, files, want in cases:
    got = lead.pr_guarded(full, pr, files)
    print(("ok   " if got == want else "FAIL ") + name)
    fails += got != want
print("test_lead_time: %d FAIL" % fails)
sys.exit(1 if fails else 0)
PY
