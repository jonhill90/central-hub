# Central Hub platform: product requirements

**System:** 8, Platform (runs Central Hub). **Status:** draft for Jon's review. **Rules for this page:** D-0007 rule 1; it sits at `docs/PRD.md` under D-0008.

This page says what the platform is for and how we know it works. It holds no "how": how lives in decision records (`docs/decisions/`), specs (`docs/specs/`) and runbooks (`docs/runbooks/`).

```
   people and agents ──▶ ┌──────────────────────── Central Hub (system 8) ────────────────────────┐
   (each its own         │  identity · secrets · storage · data · networking · backup · monitoring │
    identity)            │  ─────────────────────────────────────────────────────────────────────  │
                         │  upstream Kubernetes, run from this repo (GitOps)                       │
   apps in their own ──▶ │  ─────────────────────────────────────────────────────────────────────  │
   repos consume it      │  any site: a rented VPS today; home lab and cloud later                 │
                         └─────────────────────────── over a private network ──────────────────────┘
```

## Goals

1. **Run upstream Kubernetes on any site.** Start on one rented VPS; add home and cloud sites without redesign.
2. **Provide shared services** to the apps and agents that use the platform: identity, secrets, storage, data, networking, backup and monitoring.
3. **Jon understands every piece.** Each one is explained before it is added: purpose, dependencies and how it fails (SR01).
4. **Every piece can be replaced** without data loss, through portable formats and explicit boundaries. Each decision record names its exit path (SR02, SR11).
5. **Every human and agent has its own identity,** and every action is attributed to it (SR03).
6. **Everything is code in this repo.** No change by clicking in a console.
7. **The current state and the next step are always visible** (SR06).

## Non-goals

- The apps themselves. They live in their own repos and consume the platform.
- Research and knowledge. That is the Research repo's job, not this one's.
- Depending on one vendor (SR08).
- Agents running unattended on personal devices (SR19).
- Serving other people's production workloads.

## Success signals

| Signal | How it is checked |
|---|---|
| The cluster can be rebuilt from this repo and its runbooks alone | A rebuild on a fresh machine, following only `docs/runbooks/` |
| One component can be swapped with a bounded change | The swap touches only that component's folder and records, and nothing that uses it |
| Every component has a decision record that names its exit path | `docs/decisions/README.md` |
| A fresh reader finds the current state and next step from README | Ask a new agent session; it answers from README links alone |
| The Activation gate holds before any cluster reads this repo | The 7 items in `AGENTS.md`, each recorded |

## Links (read when)

- **Requirement rows SR01-SR25:** the requirements register in the Research repo, `coordinator/system/REQUIREMENTS.md`. Read it when a goal above needs its exact wording. The link moves when the register moves.
- **Decisions:** `docs/decisions/README.md`. Read it when you need to know why something is the way it is.
- **Changes in progress or finished:** `docs/specs/README.md`. Read it before starting a change that spans several sessions or crosses systems.
- **The pillars it is measured against:** D-0005.
