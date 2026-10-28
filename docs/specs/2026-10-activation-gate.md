---
title: Pass the Activation gate, so a cluster may read central-hub
status: proposed
date: 2026-10-28
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Pass the Activation gate, so a cluster may read central-hub

## What and why

c1 runs Argo CD with no source: nothing on the cluster reads this repository (D-0023 rule 4). AGENTS.md lists 7 things that must be true and recorded before any cluster reads it, because a GitOps engine applies whatever lands on `main`. Today an agent acts on GitHub as the owner, so GitHub can't tell the owner's approval from an agent's, and an agent's merge could change a live cluster. On 2026-10-28 the owner chose to keep the gate: Argo CD stays idle until all 7 items are recorded.

This change makes each item true, records the evidence for each, and only then lets c1 read `kubernetes/clusters/c1/`. It serves PRD goal 5 (every human and agent has its own identity) and goal 6 (everything controllable from this repo), and the success signal "The Activation gate holds before any cluster reads this repo". It spans several sessions and crosses GitHub, the agents' environment and c1, so it gets a spec (D-0007 rule 2).

```mermaid
flowchart LR
  AG1["1 agent identities"] --> AG2["2 verifier the PR can't edit"]
  AG1 --> AG7["7 break-glass recorded"]
  AG3["3 no write tokens in PR code"] --> G{all 7 recorded}
  AG4["4 no-writer Argo CD install"] --> G
  AG5["5 defined deploys"] --> G
  AG6["6 no image automation"] --> G
  AG2 --> G
  AG7 --> G
  G --> S["k8s_gitops source tag:<br/>c1 reads kubernetes/clusters/c1/"]
```

*In words:* items 3, 4 and 6 are already true and get a check or evidence. Item 5 needs Argo CD limits, which this change adds. Items 2 and 7 depend on item 1, because a checker the PR can't edit and a break-glass path only the owner holds both need agents that are not the owner on GitHub.

The plan behind the items is the Foundation proposal's §6 (v0.4.3, accepted for the Foundation stage on 2026-10-12). The measured state on 2026-10-28 comes from research batch RB-0093, which builds on RB-0018 for item 1.

### Items and their state on 2026-10-28

| Item | State | What this change adds | The owner's part |
|---|---|---|---|
| 1. Per-agent GitHub identities, with the owner's approval required by GitHub | Not true. Every agent session acts as the owner's account, and the agents' environment replaces any other GitHub key an agent sends. `protect-main` asks for 0 approvals. | The ruleset change (below) and a test plan, once the identity route is chosen | Choose the route; create the identity; change the settings |
| 2. A verifier the PR can't edit | Partly. The four docs checks are required and pinned to the GitHub Actions app. The hosts and gate checks are not required. Agents can push workflow files, so a PR can change the checks that judge it. | The required-check list for the ruleset | Choose where the verifier lives; add the checks to the ruleset |
| 3. No write tokens in PR code | True. Every workflow runs on `pull_request` with a read-only token, no secrets and no persisted checkout credential. | `.github/gate-check/check_gate.py`, run by the `gate` workflow on every PR, with its own test cases | Accept |
| 4. A pinned, no-writer GitOps engine install | True. Argo CD v3.5.5 from the upstream manifest, checked by SHA-256, no git credential (D-0023). | Evidence only | Accept |
| 5. Defined deploys | Not true. The Application would use Argo CD's `default` project, which allows any repository, destination and kind, and the application controller's ClusterRole allows every verb on every resource. | AppProject `c1` (central-hub only, this cluster only, no `kube-system` or `argocd`, cluster-scoped kinds by allow list); `default` emptied; a pause switch (`k8s_gitops_sync_paused`) | Choose how far to cut the controller's own rights |
| 6. No image automation | True. The install has no Image Updater, and Flux's image controllers are deleted by the role's kustomization. | The same check as item 3 fails on any image automation | Accept |
| 7. Break-glass recorded outside agents' reach, ruleset history confirmed | Partly. Agents get 403 on ruleset history. The admin kubeconfigs stay on the node (D-0022). | The runbook [Use break-glass access](../runbooks/use-break-glass-access.md) | Run the ruleset-history check once with the owner's own login; record each break-glass use in the project chat |

### Item 1: ruleset change, whichever identity route is chosen

Foundation proposal §6 AG1(d), unchanged: two rulesets, because a bypass skips every rule in its ruleset.

- `protect-main` keeps no bypass and keeps its rules, and the required checks move into it, so nobody merges red.
- A new ruleset `main-review` holds only the review rule: 1 approval, code-owner review on (CODEOWNERS `* @jonhill90`), approval of the last push on, and one bypass actor, the repository admin role in `pull_request` mode, so the owner's own PRs merge without self-approval.

That bypass is safe only when the owner's login is the only admin principal, so it is applied after item 1's identity works, never before.

### Item 5: what the Argo CD limits are

- **Project `c1`.** Source: central-hub only. Destination: this cluster, any namespace except `kube-system` and `argocd`. Cluster-scoped kinds: `Namespace` only; each new kind is a PR.
- **`default` emptied.** As Argo CD's projects guide shows, so an Application without a project is refused.
- **Pause switch.** `k8s_gitops_sync_paused: true` adds a deny sync window that is always active, so Argo CD syncs nothing until it is false again. This is the suspend half of item 5's "a tested suspend and recovery", and the cluster half of break-glass.
- **Synced revision.** Each activation run and each sync test records the Application's synced commit and health in its run report, kept apart from `main`.

## Out of scope

- Turning on the source (`k8s_gitops_source_enabled: true`). That is the step after this spec is `done`, and it has its own run with the owner's go-ahead.
- Moving add-ons that Ansible installs today under Argo CD.
- Identities for agents outside this project, such as a local coding agent. Each gets its own approval channel and identity before it gets write access (AGENTS.md rule 1).
- Secrets for apps (BUILD-PATH S14).

## Acceptance criteria

The criteria below were written by the agent that wrote the gate check and the Argo CD limits. An agent that wrote neither still has to review them (D-0007 rule 4).

### Automated

- [ ] `python3 .github/gate-check/check_gate.py .`: prints `gate: items 3 and 6 pass`.
- [ ] `bash .github/gate-check/tests/test_check_gate.sh`: every case prints `ok`. The cases are a `pull_request_target` trigger, a write permission at the top and in a job, a checkout that keeps its token, an action pinned to a tag, a secret read, a Flux image automation object and the Argo CD Image Updater.
- [ ] `.github/hosts-check/run.sh manifests`: AppProject `c1` and the emptied `default`, with and without the pause switch, pass kubeconform against the pinned AppProject schema.
- [ ] The `gate` workflow and the four `hosts` jobs are required checks on `main`, pinned to the GitHub Actions app (item 2).

### Manual (what the owner checks)

- [ ] Item 1: an agent's commit and PR show the agent's identity, not the owner's; a PR an agent opened can't merge until the owner approves its last push; a PR with a failing required check can't merge, even through the owner's bypass (Foundation V12).
- [ ] Item 2: a test PR that changes a check to always pass does not turn the required check green, or is refused at push.
- [ ] Item 5, on c1 after the source is on: an Application aimed at another repository or at `kube-system` is refused; with the pause switch on, a new commit under `kubernetes/clusters/c1/` is not synced; with it off again, it syncs, and the run report records the synced commit.
- [ ] Item 7: the owner reads `GET /repos/jonhill90/central-hub/rulesets/<id>/history` with their own login and it returns versions (Foundation V11); the runbook is followed once as a drill.

## Decision log

- 2026-10-28: the owner chose to keep the gate, so Argo CD on c1 stays with no source until all 7 items are recorded.
- 2026-10-28: the agents' environment was measured to replace any GitHub key an agent sends with the owner's, which rules out per-agent GitHub Apps from cloud threads as they run today. The identity route is the owner's open question.

## Points to (read when)

- [AGENTS.md](../../AGENTS.md) "Activation gate": read for the 7 items as written.
- [D-0023](../decisions/0023-use-argo-cd-as-the-gitops-engine.md): read for the Argo CD install and its rule 4, no source before the gate.
- [D-0022](../decisions/0022-reach-clusters-by-ssh-now-and-keep-admin-kubeconfigs-for-break-glass.md): read for the cluster's break-glass credential.
- [`hosts/ansible/roles/k8s_gitops`](../../hosts/ansible/roles/k8s_gitops/): read for the source switch, the projects and the pause switch.
- [Use break-glass access](../runbooks/use-break-glass-access.md): read before using any emergency path.
