---
title: Set up the VPS apps host
status: draft
kind: automated
trigger: once for the VPS, after D-0046's record and the agent box's vps-host wrapper are installed; apply again after each change to role vps_app_host
runner: the pipeline job .github/workflows/lab-vps-host.yml on the agent box's runner, through the box's `vps-host` wrapper
outcome: the VPS has one Linux user per app with rootless Podman, user deploy whose sudo allows vps-apply only, Valkey on loopback with a password made on the host, and nothing new listening on a public address
needs: D-0046; the agent box with the vps-host wrapper installed (a box limit, D-0036 rule 3); the tailnet steps S1 and S4 of D-0046 rule 4; the private inventory value below
private-values: [vps-name]
files: [hosts/ansible/roles/vps_app_host/, hosts/vps-apps/, hosts/ansible/playbooks/vps-app-host.yml, hosts/ansible/roles/agent_box/files/vps-host.sh, .github/workflows/lab-vps-host.yml]
last-tested: not yet run
superseded-by:
---

# Set up the VPS apps host

**Status:** draft, not run. Written on 2026-11-14 from the code in this PR, the AlmaLinux 10 package lists measured on the VPS, and the docs named in D-0046's evidence. The record is [D-0046](../decisions/README.md), merged with status proposed.

## What it builds

- **Packages** from AlmaLinux 10's own repositories: Podman, catatonit, Valkey, git and ansible-core.
- **One Linux user per app**: `omniroute`, `openclaw` and `hermes`. Each has no password and no login shell, subordinate IDs for rootless Podman, and linger, so its own services run with no one signed in.
- **User `deploy`**, the box's only way in after the narrowing. Its sudo allows `/usr/local/sbin/vps-apply` with the first arguments `host`, `secrets`, `secrets rotate` and `status`, and nothing else.
- **`vps-apply`**, which lets the VPS apply this role to itself from reviewed `main`, as the agent box does (D-0036). `vps-apply host <commit>` refuses a commit that is not on `main`.
- **Valkey** bound to 127.0.0.1 and ::1, with protected mode on, and its password read from a file that only `vps-apply secrets` writes. Valkey stays off until that file exists.
- **A check** that fails the run if any port other than 22 listens on an address that is not loopback or the tailnet's. Port 22 is the owner's own sshd, which this runbook does not change.

No secret is made by the role. `vps-apply secrets` makes Valkey's password and OmniRoute's own secrets, after the narrowing (D-0046 rule 4, S5).

## Before you start

- D-0046 is accepted.
- The agent box has the `vps-host` wrapper and its sudo rule. Both are box limits, so they are installed on the agents' pass of their digest, with no owner card (D-0042 rule 4), by an apply from the controller, because the VPS's name below is a new inventory value (D-0046 rule 5). Until then, steps 1 and 2 wait. That keeps the agents' tailnet access to the VPS as it is until the box can do the work (D-0046 rule 5).
- The box's inventory sets `agent_box_vps_host: {name: <vps-name>}`, the VPS's name on the tailnet. It is private, so it is never written here.

## Steps

1. **The owner's go and tailnet step S1.** Each of S1, S4 and S6 gets the owner's go of its own (his typed line, or his tap on a card option the card did not recommend (D-0034 rule 9)), naming that one step and its commit, one step at a time, in that order and each when its step is next (D-0046 rule 6 lets the cards come back to back). S2 (the box's wrapper and sudo rule) is installed first, with no card (D-0042 rule 4), because S1 waits until S2 is installed (D-0046 rule 5). S1 also waits for the tailnet policy job's hold to lift: no plan or apply until the policy template carries the group and `externalTailnets` entry the live policy holds ([Change the tailnet policy file through the pipeline job](run-the-tailnet-policy-as-a-pipeline-job.md)). After S1's go, the tailnet policy job applies S1 (`.github/workflows/lab-tailnet-policy.yml`, plan then apply; [Change the tailnet policy file through the pipeline job](run-the-tailnet-policy-as-a-pipeline-job.md)).
   expect: the tailnet lets the box sign in to the VPS as `root` and `deploy`, and lets agent sessions sign in as `deploy` only.
2. **Bootstrap (S3), once.** Start `lab-vps-host` with action `bootstrap`.
   why: `deploy` and `vps-apply` don't exist yet, so the first apply signs in as root.
   expect: the job prints `vps-host: bootstrap ok`. The box's log holds the playbook's output.
3. **Tailnet step S4.** After S4's own card, the tailnet policy job applies S4, which drops `root` from the box's login and adds the `sshTests`.
   expect: the tailnet accepts the new policy, so its tests passed. From then on, `bootstrap` is refused by the tailnet.
4. **The host's secrets (S5).** Start `lab-vps-host` with action `secrets`.
   expect: it prints which secrets it made, never their values: `valkey password`, `VPS_OMNIROUTE_API_KEY` and `VPS_OMNIROUTE_WS_BRIDGE_SECRET`. Valkey starts.
5. **Check.** Start `lab-vps-host` with action `status`.
   expect: the last good host apply is named; Valkey's password file is present; Valkey is `active`; and `valkey proof: pass`, which means a client with no password was refused and one with the password got `PONG`.

**The apps' units.** Each app is a Quadlet unit in `hosts/vps-apps/<app>/<app>.container` (OmniRoute 2.5 GiB, OpenClaw 3 GiB, Hermes Agent 4 GiB, D-0046 rule 1), pinned to an image digest, with its host port on 127.0.0.1 only (OmniRoute 20128, OpenClaw 18789, Hermes none). Every `apply` copies each file to its app user's `~/.config/containers/systemd/`, runs `systemctl --user daemon-reload` as that user, and fails if the generated service carries no `--memory` cap. The units are installed, never started by the role: each skips itself until `~/.config/vps-apps/secrets.env` exists, which `vps-apply secrets` makes for OmniRoute (S5). Not done yet: OpenClaw and Hermes have no secrets file until the provider key step (S7) and their own config; the names `vps-apply` writes (`VPS_*`) are not yet the names OmniRoute reads, so a change must map them before OmniRoute's first real start. Linger is on and each unit has `WantedBy=default.target`, so once `secrets.env` exists a unit also starts at every boot of the VPS, with no apply. Images are pinned to the newest release at least two weeks old (STD-0003 rule 1; the version is in a comment above each `Image=`). To move to a newer image, change the digest in the unit file and merge.

**Close the public SSH door (off until the owner's card).** The role's `harden.yml` turns off sshd password login, sets root to key only, and turns on firewalld with the tailnet's interface trusted and port 22 and Tailscale's UDP port open, only when `vps_app_host_harden` is `true` in the inventory. It refuses to start unless Tailscale SSH is on, the tailnet interface exists and root has some authorized key (the card says password login ends), and it checks `sshd -t` and the live firewall afterwards. Tailscale SSH does not go through sshd, so the agents' way in is untouched. Not run: it waits for the owner's card (D-0042 rule 6).

After a change to role `vps_app_host` merges, start `lab-vps-host` with action `apply`. The VPS checks out `main`'s commit and applies the role to itself.

## Proofs

- `vps-apply status` checks Valkey itself (step 5): no password is refused, the password gets `PONG`.
- Every apply fails if a port other than 22 listens on a public address (the role's last task).
- The sudo rule is checked with `visudo` before it is written, and lists `vps-apply` only.
- **The VPS's host key is trusted on first use, on purpose for now.** `vps-host` connects with `StrictHostKeyChecking=accept-new` and its own known-hosts file, so the first run records the key and any later run against a changed key stops. The box reaches the VPS only over the tailnet, where Tailscale's node keys already prove which node answers at that address ([Tailscale SSH](https://tailscale.com/docs/features/tailscale-ssh)). Pinning the key in the box's private inventory is a later step, not built.

## Way back

- To undo a role change, start `apply` after the revert merges. `vps-apply host` takes any commit on `main`.
- To make new secrets, run `secrets-rotate`. Services that read them restart with them.
- To remove the setup, the owner deletes the app users and packages; that is a delete, so it is the owner's step (D-0042 rule 6). The VPS itself is never torn down (D-0035 rule 2).
