# Runbooks

A runbook is a page for one job, step by step: `docs/runbooks/<verb>-<object>.md`. The format, the status words and the step rules are set in [D-0012](../decisions/0012-sort-docs-by-kind-of-document.md) ("Runbook format" and "Runbook steps"). Each step has a short `why:` line and links back with ※ to what it relies on. Each runbook is marked `manual` or `automated`, and for any job the `manual` runbook comes first.

A runbook is living: it is edited in place, and git keeps the history. No hostnames, single machine addresses, contacts or secrets are written here; a runbook names the key that holds a value in the private store (D-0012 rule 10).

| Runbook | Kind | Status |
|---|---|---|
| [Build a single-node kubeadm cluster by hand (CKA practice)](build-kubeadm-cluster.md) | manual | draft |
| [Set up a Proxmox VE host by hand](set-up-proxmox-host.md) | manual | draft |

## Template

```markdown
---
title: <task, verb first>
status: draft            # draft | tested | superseded | retired
kind: manual             # manual | automated
trigger: <alert, schedule, event, or "on request">
runner: <Jon, or an agent lane>
outcome: <what is true when it is done>
needs: <tools and permissions>
private-values: [<key names in the private store; never the values>]
files: [<paths this runbook runs or reads>]
last-tested: <YYYY-MM-DD, who ran it, on what>
superseded-by:
---

# <title>

## Before you start
<check the current state; stop if it is not what this runbook expects>

## Steps
1. <one action: the exact command, or a link to the script>
   why: <one or two sentences: why this step, and how it connects to the last one>
   ※ <optional: what this relies on, linked to where it is explained>
   expect: <what you should see>

## If it fails
<where to stop, how to undo, and when to tell Jon>

## Afterwards
<what to record and where: a postmortem after an incident, a spec's done-evidence after a build>

## Related
<the decision, spec, standard or postmortem behind it>
```
