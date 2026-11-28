---
title: Set up OpenClaw on the VPS
status: draft
kind: automated
trigger: once, after the VPS apps host is built and D-0046 is accepted; again after a change to OpenClaw's unit file
runner: the pipeline job .github/workflows/lab-vps-host.yml on the agent box's runner, through the box's `vps-host` wrapper
outcome: OpenClaw's gateway runs as a rootless Quadlet unit of Linux user `openclaw`, listens on the VPS's loopback only, sends no update check or telemetry, and answers through OmniRoute with the owner's provider key
needs: the VPS apps host runbook done through its step 5; D-0046 accepted; the provider key stored (D-0046 rules 6 and 7); the private inventory value of that runbook
private-values: [vps-name]
files: [hosts/vps-apps/openclaw/openclaw.container, hosts/ansible/roles/vps_app_host/, docs/decisions/0046-run-omniroute-openclaw-and-hermes-agent-on-the-vps-in-rootless-podman-with-no-lab-reach.md]
last-tested: not yet run
superseded-by:
---

# Set up OpenClaw on the VPS

**Status:** draft, not run. Written on 2026-11-28 from the unit file on `main`, [D-0046](../decisions/README.md) (still proposed), and OpenClaw's README and docs ([README](https://github.com/openclaw/openclaw), [Docker](https://docs.openclaw.ai/install/docker), [telemetry](https://docs.openclaw.ai/gateway/telemetry)). The VPS itself was measured the same day: the user, linger and unit file exist, the unit is inactive, and no `secrets.env` exists. Anything marked *not tested* below has not been seen working.

## What it builds

- **OpenClaw's gateway**, MIT with no paid tier, from OpenClaw's own image `ghcr.io/openclaw/openclaw`, pinned by digest in the unit file. It runs under user `openclaw` in rootless Podman with a 3 GiB memory cap (D-0046 rules 1 and 2).
- **One published port**, `127.0.0.1:18789`, on the VPS. Nothing listens on a public address (D-0046 rule 3).
- **No update check and no telemetry.** OpenClaw checks for updates daily and reports version and platform by default. The unit sets `OPENCLAW_NO_AUTO_UPDATE=1` and `DO_NOT_TRACK=1`, the two switches its docs name. *Not tested* against a running gateway.
- **Tools off.** OpenClaw runs tools on the host unless sandboxing is set up, so they stay off until the sandbox proof of D-0046 rule 9.
- **No chat channel.** D-0046 rule 6 (J4) gives no bot token at first. Direct-message channels pair unknown senders by default, so adding one later is its own step.

## Before you start

- The [VPS apps host runbook](set-up-the-vps-app-host.md) is done through its step 5, so `vps-apply status` reports `valkey proof: pass`.
- D-0046 is accepted and the owner has done J1 and J2 (the provider key is in the secrets store). S6 and S7 then put it on the VPS. Until they have, the unit skips itself (`ConditionPathExists` on `secrets.env`).
- The image digest is at least two weeks old (STD-0003 rule 1). The digest in the file dates from 2026-11-02; a newer release may pass the rule now. Check it before the first start and change the digest in the unit file by pull request.

## Steps

1. **Check the pin.** Read the image's newest release tag and date on [GitHub Container Registry](https://github.com/openclaw/openclaw/pkgs/container/openclaw). If one is at least two weeks old, change the `Image=` digest and the version comment in `hosts/vps-apps/openclaw/openclaw.container` by pull request.
   why: the pin is the only thing that decides which code runs as `openclaw`, and the VPS never builds.
   expect: the merged file names one digest and its release date.
2. **Apply the host role.** Start `lab-vps-host` with action `apply`.
   why: every apply copies the unit file to the user's `~/.config/containers/systemd/` and fails if the generated service has no `--memory` cap.
   expect: the job's log shows the playbook with `failed=0`; the unit file on the VPS matches `main`.
3. **Start the unit.** Once `secrets.env` exists, the unit starts at the next boot or after `systemctl --user restart openclaw` as user `openclaw`. *Not built:* `vps-apply` has no start action for apps yet, so this step needs one added by a pull request before an agent can do it through the pipeline.
   expect: `systemctl --user -M openclaw@ is-active openclaw` prints `active`.
4. **Point it at OmniRoute.** OpenClaw reads its model provider from its own config in `~/data` (a custom provider with a base URL, [model providers](https://docs.openclaw.ai/concepts/model-providers)). OmniRoute listens on the VPS's loopback, and a rootless container does not see the host's loopback by default, so how OpenClaw reaches it is open. *Not tested; not designed.* Decide it on the rehearsal VM (D-0046 rule 12) before this step runs on the VPS.
5. **Open the dashboard.** The owner opens an SSH tunnel over the tailnet to `127.0.0.1:18789` and pastes the gateway token. D-0046 rule 3 chose this over Tailscale Serve. The token is made on first start and kept in the user's data folder; never print it into a log.

## Proofs

- `ss -tlnH` on the VPS shows 18789 only on `127.0.0.1`, and the apply's last task still fails if any port other than 22 listens publicly.
- `podman inspect openclaw` as user `openclaw` shows the memory limit 3 GiB and the two `Environment` values. *Not tested.*
- The sandbox proof of D-0046 rule 9, run on the rehearsal VM first: a tool call runs in a sandbox container; from inside it, the user's env file and OmniRoute's and Valkey's loopback ports cannot be reached; root's Podman holds no container. If any check fails, OpenClaw runs with tools off. *Not run.*
- A message through the dashboard gets a reply from the provider. *Not tested.*

## Way back

- To stop it: `systemctl --user stop openclaw` as user `openclaw`; the data stays in `~/data`.
- To undo a unit change, revert the file and start `apply`.
- To remove OpenClaw, the owner deletes the user; that is a delete (D-0042 rule 6). The VPS itself is never torn down (D-0035 rule 2).

## Related

- [Set up the VPS apps host](set-up-the-vps-app-host.md)
- [Set up Hermes Agent on the VPS](set-up-hermes-agent-on-the-vps.md)
