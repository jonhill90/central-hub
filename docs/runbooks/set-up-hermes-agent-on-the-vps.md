---
title: Set up Hermes Agent on the VPS
status: draft
kind: automated
trigger: once, after the VPS apps host is built and D-0046 is accepted; again after a change to Hermes Agent's unit file
runner: the pipeline job .github/workflows/lab-vps-host.yml on the agent box's runner, through the box's `vps-host` wrapper
outcome: Hermes Agent's gateway runs as a rootless Quadlet unit of Linux user `hermes` with no published port and no dashboard, and answers through OmniRoute with the owner's provider key
needs: the VPS apps host runbook done through its step 5; D-0046 accepted; the provider key stored (D-0046 rules 6 and 7); the private inventory value of that runbook
private-values: [vps-name]
files: [hosts/vps-apps/hermes/hermes.container, hosts/ansible/roles/vps_app_host/, docs/decisions/0046-run-omniroute-openclaw-and-hermes-agent-on-the-vps-in-rootless-podman-with-no-lab-reach.md]
last-tested: not yet run
superseded-by:
---

# Set up Hermes Agent on the VPS

**Status:** draft, not run. Written on 2026-11-28 from the unit file on `main`, [D-0046](../decisions/README.md) (still proposed), and Hermes Agent's README and docs ([README](https://github.com/NousResearch/hermes-agent), [Docker](https://hermes-agent.nousresearch.com/docs/user-guide/docker), [security](https://hermes-agent.nousresearch.com/docs/user-guide/security), [providers](https://hermes-agent.nousresearch.com/docs/integrations/providers)). The VPS was measured the same day: the user, linger and unit file exist, the unit is inactive, and no `secrets.env` exists. Anything marked *not tested* has not been seen working.

## What it builds

- **Hermes Agent's gateway**, MIT, from the image `docker.io/nousresearch/hermes-agent`, pinned by digest. It runs under user `hermes` in rootless Podman with a 4 GiB memory cap and browser tools off (D-0046 rules 1 and 2). Data lives in `~/data`, mounted at the image's `/opt/data`.
- **No published port and no dashboard.** The image exposes none, and `HERMES_DASHBOARD` stays unset. Hermes's own docs say its dashboard fails closed on a non-loopback bind without an auth provider and tie exposed dashboards to a June 2026 attack campaign, so a dashboard is a separate decision, not part of this runbook.
- **The long-running command.** The unit sets `Exec=gateway run`, the command Hermes's Docker page runs. *Not tested:* the first start shows whether the image's entrypoint takes it as written.
- **No chat channel, no Nous Portal.** D-0046 rule 1 rules out a Nous Portal subscription, and rule 6 (J4) gives no bot token at first. The model comes from an API key through OmniRoute.

## Before you start

- The [VPS apps host runbook](set-up-the-vps-app-host.md) is done through its step 5.
- D-0046 is accepted and the owner has done J1 and J2. S6 and S7 then put the key on the VPS. Until they have, the unit skips itself.
- The image digest is at least two weeks old (STD-0003 rule 1). The file's digest is v0.23.1 (built 2026-11-10, checked on Docker Hub on 2026-11-28); check for a newer release as in step 1.

## Steps

1. **Check the pin.** Read the image's newest tag and date on Docker Hub. If one is at least two weeks old, change `Image=` and its comment in `hosts/vps-apps/hermes/hermes.container` by pull request.
   expect: the merged file names one digest and its release date.
2. **Apply the host role.** Start `lab-vps-host` with action `apply`.
   expect: `failed=0`; the unit file on the VPS matches `main`.
3. **Give it its model.** Hermes reads an OpenAI-style provider from `OPENAI_API_KEY` and an optional `OPENAI_BASE_URL` in its `.env`, and a model choice in `config.yaml`, both in the data folder. Point the base URL at OmniRoute. *Not built:* no role task writes these two files yet, and `hermes setup` is an interactive wizard, so a task has to write them. OmniRoute is on the host's loopback, which a rootless container does not see by default, so the route is open, as in the [OpenClaw runbook](set-up-openclaw-on-the-vps.md) step 4. *Not tested.*
4. **Start the unit.** As for OpenClaw: after `secrets.env` exists, at next boot or `systemctl --user restart hermes` as user `hermes`; `vps-apply` has no app start action yet.
   expect: `systemctl --user -M hermes@ is-active hermes` prints `active`.
5. **Check what it keeps.** Hermes learns skills and memory into `~/data`. That folder is the app's whole state; include it in the VPS's backup plan before anyone relies on it. *No backup of the VPS is set up by this runbook.*

## Proofs

- `ss -tlnH` on the VPS shows no new listener, and the apply's last task fails if any port other than 22 listens publicly.
- `podman inspect hermes` as user `hermes` shows the 4 GiB limit. *Not tested.*
- A one-shot prompt through the gateway gets a reply from the provider. *Not tested.*
- Tools: Hermes runs commands on the host unless a container backend is set, and its docs list command approval and container isolation. Which of its terminal backends is safe inside this unit is open; it gets its own proof like OpenClaw's rule 9 before any tool is switched on. *Not run.*

## Way back

- To stop it: `systemctl --user stop hermes` as user `hermes`; the data stays.
- To undo a unit change, revert the file and start `apply`.
- To remove it, the owner deletes the user (a delete, D-0042 rule 6). The VPS itself is never torn down (D-0035 rule 2).

## Related

- [Set up the VPS apps host](set-up-the-vps-app-host.md)
- [Set up OpenClaw on the VPS](set-up-openclaw-on-the-vps.md)
