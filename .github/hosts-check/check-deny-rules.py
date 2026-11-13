"""Check the agent box's managed deny rules for forms Claude Code ignores (measured on the box,
2026-11-13: a `*` mixed with a trailing `:*` is matched as a literal prefix, and Write(path)
rules are not matched because Edit(path) covers every file-editing tool). Also fails if the
raw tofu apply and destroy rules, with and without -chdir, are missing."""
import re
import sys

import yaml

rules = yaml.safe_load(open("hosts/ansible/roles/agent_box/defaults/main.yml"))["agent_box_deny"]
bad = []
for r in rules:
    if r.startswith("Write("):
        bad.append(f"{r}: Write(path) rules never match; use Edit(path)")
    m = re.match(r"Bash\((.*):\*\)$", r)
    if m and "*" in m.group(1):
        bad.append(f"{r}: * mixed with a trailing :* is matched literally; end with plain *")
need = ["Bash(tofu apply:*)", "Bash(tofu destroy:*)", "Bash(tofu -chdir=* apply*)", "Bash(tofu -chdir=* destroy*)"]
bad += [f"missing rule: {n}" for n in need if n not in rules]
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
print(f"deny rules ok ({len(rules)})")
