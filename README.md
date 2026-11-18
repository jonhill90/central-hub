# central-hub

The Central Hub platform repository.

**Status: Foundation.** The lab cluster c1 runs from this repository: Argo CD reads it read-only (D-0027), and the apps it installs are in `hosts/kubernetes/home/c1/apps/`. The secrets store, OpenBao, runs in prod's c1 since 2026-11-18 (`docs/runbooks/set-up-the-secrets-store.md`). No other cluster reads this repository until the Activation gate in `AGENTS.md` passes. Each change is a pull request that the reviewer clears; Jon taps only for the steps D-0042 rule 6 keeps (`AGENTS.md` rule 1).

- What the platform is for: `docs/PRD.md`
- Decisions: `docs/decisions/`
- Changes (specs): `docs/specs/`
- Agents: start with `AGENTS.md`
- Security reports: `SECURITY.md`
