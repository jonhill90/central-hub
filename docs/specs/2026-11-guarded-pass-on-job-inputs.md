---
title: Tie a guarded apply's pass to the files the job reads, not to main's commit
status: proposed
date: 2026-11-23
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Tie a guarded apply's pass to the files the job reads, not to main's commit

## What and why

`opnsense-prod.sh` and `tailnet-stack.sh` on the agent box record the reviewer's pass and the go against main's commit (`pass-<job>-<commit>-<hash>.jsonl`, `go-<job>-<commit>.jsonl`, `opnsense-prod.sh` lines 84 to 92). `apply-recorded` fetches `origin/main` again before it applies (line 142). So any merge to `main` voids a recorded pass, even one that touches nothing the job reads, and the job needs a new check and a new reviewer round. On 2026-11-23 this happened three times for one firewall change. Between 2026-11-22 18:00 UTC and 2026-11-23 03:00 UTC, 29 PRs merged to `main`. Only 3 of them changed a file the firewall job reads, and 2 changed the tailnet folder.

This spec keys the pass and the go to an **inputs digest**: a hash of the git objects for exactly the paths the job reads, at the commit it runs. A merge that leaves those paths unchanged leaves the digest unchanged, so the recorded pass still holds. A merge that changes one of them changes the digest, so the pass no longer matches and the job refuses, as it does now. This serves the PRD's aim of fast, safe changes (D-0065 rule 5) and keeps D-0036 rule 8: a firewall or tailnet apply still needs its pass and its go.

## How

1. Each job names its inputs in the wrapper, as a fixed list:
   - `opnsense-prod`: `hosts/ansible/playbooks/opnsense.yml`, `hosts/ansible/playbooks/tasks/opnsense-tls.yml`, `hosts/ansible/roles/opnsense_lab`, `hosts/ansible/ansible.cfg`, `hosts/ansible/requirements.yml`, `hosts/ansible/inventories/home/group_vars/all/vlans.yml`.
   - `tailnet-stack`: `hosts/terraform/home/tailnet`.
2. The inputs digest is the first 12 hex digits of SHA-256 over the lines `<path> <git rev-parse <commit>:<path>>`, in the list's order. A path that is missing is an error, never an empty line.
3. `check` (or `plan`) prints and saves the commit, the inputs digest and the check hash. `pass` and `go` take the inputs digest in place of the commit, and the ledger file names use it.
4. `apply-recorded` fetches `origin/main`, works out the digest again, reruns the check, and applies only if both the digest and the check hash match a recorded pass and an unspent go. Its log line still names the commit it ran.
5. The job refuses when a role or playbook it reads pulls in a file outside the list: a `dependencies:` entry in a listed role's `meta/main.yml`, or an `import_*` or `include_*` path that is not listed. So the list cannot quietly fall behind the code.

## Out of scope

- No change to the wrappers in this PR. The code change is a later box-limit install, which goes through the reviewer's digest pass (D-0044).
- No change to who may pass or give a go, or to which jobs are guarded (AGENTS.md rule 2).
- The Proxmox host job (`proxmox-host.sh`) keeps its commit binding for now. Its inputs are wider, and a later PR can list them.

## Acceptance criteria

### Automated

- [ ] `bash .github/hosts-check/tests/test_opnsense_prod_args.sh` and `test_tailnet_stack_ledger.sh`, with new cases:
  - a pass recorded at commit A still applies at a commit B that changes only `docs/`;
  - it refuses at a commit C that changes `roles/opnsense_lab`;
  - it refuses when the check hash differs;
  - it refuses when a listed role gains a `meta/main.yml` dependency that is not listed;
  - it refuses when a listed path is missing.
- [ ] The log line of an apply names the commit it ran and the inputs digest.

### Manual (what the owner checks)

- [ ] None. The reviewer checks the wrapper change at its box-limit install.

## Points to (read when)

- `hosts/ansible/roles/agent_box/files/opnsense-prod.sh`: read when changing the ledger keys.
- `hosts/ansible/roles/agent_box/files/tailnet-stack.sh`: read when changing the plan step.
- `docs/decisions/0065-merge-plain-prs-on-green-and-ship-changes-without-a-rebuild.md`: read for why a change must not wait on unrelated merges.

## Decision log

- 2026-11-23: the digest is built from git object ids, not by hashing files on disk. Git already hashes them, and the result depends only on the commit, not on the checkout's state.
