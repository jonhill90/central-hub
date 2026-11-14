---
id: D-0046
title: Run OmniRoute, OpenClaw and Hermes Agent on the VPS in rootless Podman with no lab reach, narrow the VPS's SSH logins before any key lands, and keep their config in hosts/ until the agents can make repos
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0038, D-0041, D-0042]
supersedes: []
superseded-by:
revisit-when: an app needs more memory than its cap or the VPS has; an app needs to reach the lab or a model on the home GPU; the owner wants a chat channel for an app; the agents get a GitHub account that can create repositories (D-0030); OpenBao's production store or the owner's sign-in to it changes; or the VPS is replaced
---

# Run OmniRoute, OpenClaw and Hermes Agent on the VPS in rootless Podman with no lab reach, narrow the VPS's SSH logins before any key lands, and keep their config in hosts/ until the agents can make repos

## Context and Problem Statement

At 08:23:08 UTC on 2026-11-14 the owner asked to host OpenClaw and Hermes on his VPS, as part of the lab's network, and said the lab also needs OmniRoute (cmsg_01X43rfNYp4H1dL1V2dkfkwNB4NvHXxTVXu6Mw171TiuAq).

- **OpenClaw** (`openclaw/openclaw`) and **Hermes Agent** (`NousResearch/hermes-agent`) are self-hosted AI agents that run tools and talk to chat platforms. **OmniRoute** (`cheaper-inference/OmniRoute`, formerly `diegosouzapw/OmniRoute`) is a gateway that gives one OpenAI-style endpoint in front of many model providers.
- The VPS is already a node on the lab's tailnet, tagged `tag:vps`. No grant has `tag:vps` as its source, so it starts no connection to the lab. It has 4 vCPU, 15 GiB of memory and 199 GB of disk, and runs nothing yet.
- Today `tag:agent` and `tag:github-actions` may log in to it as root (the tailnet policy's `ssh` block). Agents that hold API keys must not sit on a host where every agent session is root.
- The repository's PRD says the apps themselves "live in their own repos" (`docs/PRD.md`, Non-goals), but the agents cannot create a repository.
- No D-0038 secrets store holds real secrets yet, and the owner has no sign-in to one.

## Decision Drivers

- **The owner's ask**: the three apps on his VPS, on the lab's network.
- **No lab reach for internet-facing agents**: they read untrusted messages and run tools.
- **No key on a host where agent sessions are root.**
- **FOSS with no paid feature in use, and an exit path** (STD-0006, REQ-0032).
- **Every change through the pipeline** (D-0041), and the owner's taps only for what D-0042 rule 6 keeps.
- **Never the owner's Claude subscription**: Anthropic does not let third-party products route requests through Free, Pro or Max plan credentials.

## Considered Options

1. **The VPS, rootless Podman, one user per app, loopback only**, reached over the tailnet by SSH tunnel.
2. **A VM in the home lab.**
3. **The VPS with a rootful container engine**, all apps under one user.
4. **Don't host them**: use hosted equivalents.

## Decision Outcome

Proposed: **option 1**. Every rule below is an agent pick unless it cites the owner.

Diagram: not applicable. The apps add no route to the lab; the only network paths are the tailnet SSH logins in rule 4.

### Rules

1. **What runs.** OmniRoute, OpenClaw and Hermes Agent, all MIT with no paid edition in use, and Valkey (BSD-3-Clause) as OmniRoute's Redis-protocol store. Not Redis: Redis Ltd holds features back in a paid edition (STD-0006 rule 2). Light use only, with memory caps: OpenClaw 3 GiB, Hermes Agent 4 GiB with browser tools off, OmniRoute 2.5 GiB, Valkey 0.5 GiB, about 10.5 of 15 GiB with the system. No local model on the VPS. No Nous Portal subscription.
2. **How it runs.** Each app runs under its own Linux user, in that user's rootless Podman from AlmaLinux's own packages. OpenClaw's gateway runs as a plain process of its user (Node 24 from AlmaLinux), and its tool sandboxes run in that user's rootless Podman (`sandbox.backend: "podman"`), so there is no Podman inside Podman.
3. **No new listener on the public address.** Every app binds to 127.0.0.1. The owner reaches a dashboard by an SSH tunnel over the tailnet, which `autogroup:admin` may already open. Tailscale Serve is not used: it needs the tailnet's HTTPS certificates turned on, which they are not, and turning them on publishes the machine names to a public ledger. The VPS gets no grant into the lab, and a policy test proves `tag:vps` reaches no lab address.
4. **SSH logins are narrowed before any key, token or secret lands.** In this order, each a pipeline job:
   - **S1**, tailnet apply 1: remove `tag:github-actions`'s grant and SSH rule (nothing uses them); let `tag:agent-box` reach `tag:vps` on tcp:22 as `root` and `deploy`; narrow `tag:agent` to `deploy` only. This reverses the policy's line "tag:agent-box gets no destination of its own" and changes its deny test for `tag:vps:22`.
   - **S2**, a new box wrapper, `vps-host`, that runs the reviewed host role on the VPS over Tailscale SSH. It is a box limit (D-0036 rule 3(c), and 3(e) if it gets a timer).
   - **S3**, the first host apply, through `vps-host`, as root, once: Podman, the app users, user `deploy`, and the VPS's own wrapper `vps-apply`. `deploy` may run `vps-apply` with sudo and nothing else. No secret is made or placed.
   - **S4**, tailnet apply 2: drop `root` from `tag:agent-box`, leaving `deploy`, and add `sshTests` that deny `root` and every app user from `tag:agent` and `tag:agent-box`.
   - **S5**: `vps-apply` makes the generated secrets on the VPS (Valkey's password, OmniRoute's API key and bridge secret), each in a mode 600 file of its app user, after S4 and never before. Any made earlier is rotated.
   - **S6**: a new OpenBao AppRole for the VPS job whose policy reads only `kv/data/vps/*`.
   - **S7**: the job reads the provider key from OpenBao, and `vps-apply` writes it to OmniRoute's env file.
5. **Holds.** S1 and S3 wait until S2 is installed on the box, so `tag:agent` never loses root on the VPS before `vps-host` exists. The box limits merged on `main` are not installed until a controller apply, which today still needs the owner's Mac; S2 joins that gap.
6. **The owner's own steps, named in their smallest form.** None is hidden in a tap.
   - **J1** (money and secrets): create one model-provider API key, with billing and a monthly spend cap set in the provider's console. OmniRoute fronts all three apps, so one key serves them.
   - **J2** (secrets): type that key himself into OpenBao's web UI on 443, path `kv/vps/provider-key`. No chat paste, no Mac step, no typed line.
   - **J3**: one tap on a card that names S1, S2, S4 and S6 and their commits (D-0042 rule 6: firewall and tailnet, the box's limits, access rights). If a card may name only one plan, two cards back to back.
   - **J4**: no chat bot tokens at first. A bot token is a later step of its own, only if the owner wants a chat channel.
7. **The key intake is gated.** The apps hold no provider key until two things exist: D-0038's production store (the dev store holds nothing of value by design), and a sign-in to its web UI for the owner, which D-0038 does not give. Until then the VPS stops at S5: host built, generated secrets only, no external key.
8. **Never the owner's Claude subscription.** Only API keys; no subscription logins in OmniRoute and no CLIProxyAPI sidecar. OmniRoute uses official provider APIs only.
9. **OpenClaw's tools go live only after the sandbox proof.** On the rehearsal VM first, then the VPS: a tool call runs in a sandbox container of the `openclaw` user; from inside it, the user's env file and 127.0.0.1's OmniRoute and Valkey ports can't be reached; root's Podman holds no container. If any check fails, OpenClaw runs with tools off.
10. **The pipeline's scope.** D-0041's pipeline also covers the VPS host's setup, through `vps-host` and `vps-apply`. Never its teardown: D-0035 rule 2 keeps the VPS node out of every teardown, unchanged.
11. **Where the code lives: an exception to the PRD.** The host layer and OmniRoute are platform, in `hosts/vps-apps/`. OpenClaw's and Hermes Agent's config goes there too, in `hosts/vps-apps/openclaw/` and `hosts/vps-apps/hermes/`, although the PRD puts apps in their own repos. Reason: a GitHub App installation token can't create a repository in a personal account, and the agents' session tools may not create one. Only config goes there: no secrets, host names or chat channel ids; those stay in the private inventory.
12. **Rehearse at home first, never during a rebuild.** Each runbook runs twice on a throwaway AlmaLinux 10 VM on the dev VNet (4 GiB), with a stub provider and no key. That VM never runs during a dev rebuild run or the Sunday GPU block; the rebuild's rule counts it as a new VM to keep stopped.
13. **The CI runner stays at home** on its own VM, off the host that runs these apps.

### Consequences

- Good: the apps run with no route into the lab, and none of them listens on the internet.
- Good: once S4 is applied, no agent session can read the apps' keys, and the tailnet itself refuses a policy that brings root back.
- Good: every app and the store have an exit (below), and all are FOSS.
- Bad: the apps hold no provider key until the production secrets store and the owner's sign-in to it exist (rule 7).
- Bad: S1 and S3 wait on the box-limit install gap (rule 5).
- Bad: the box gets a path to the VPS it did not have, though only as `deploy` after S4.
- Bad: app config sits in the platform repository, against the PRD's non-goal, until the agents can make repos.
- Bad: light use only. A coding agent through OmniRoute (10 GiB or more) or Hermes with browser tools does not fit.
- Neutral: the VPS's own firewall is a step of the owner's, not changed here.

### Confirmation

- The tailnet policy's tests and `sshTests` pass on every apply: `tag:vps` reaches no lab address, and no `tag:agent` or `tag:agent-box` login as root or an app user is allowed.
- On the VPS, `ss -tlnp` shows nothing new on a public address after each apply.
- OmniRoute answers a test request through the API key; Valkey refuses a client with no password.
- OpenClaw's sandbox proof (rule 9) passes before its tools go live.
- Memory of each app is measured after 24 hours against its cap.
- The component register has rows for Podman, catatonit, Node 24, Valkey, OmniRoute and its image, OpenClaw, Hermes Agent and its image, and the model provider as `hosted`. They are added with the code that pulls them in, so the FOSS check sees each source.

### Exit path

- OmniRoute → any OpenAI-style gateway, or the apps call the provider directly.
- OpenClaw ↔ Hermes Agent: each can stand in for the other.
- Podman → any OCI runtime; the images are standard OCI images.
- Valkey → OmniRoute's in-memory fallback.
- The hosted model provider → another provider behind OmniRoute, or a local model on the home GPU after a design of its own.
- The VPS → a home VM; the host role is not tied to the provider.
- `hosts/vps-apps/openclaw/` and `hosts/vps-apps/hermes/` → their own repositories, one folder each, once the agents can create one.

## Pros and Cons of the Options

### Option 2: a VM in the home lab

- Good: no new SSH path from the box.
- Bad: the home host's memory is already fully allocated, and it is off at times.
- Bad: internet-facing agents would sit on the same host as the lab.

### Option 3: a rootful container engine

- Good: one daemon, familiar tooling.
- Bad: a container break-out is root on the host, and one user would hold every app's keys.

### Option 4: don't host them

- Good: nothing to run.
- Bad: it does not do what the owner asked.

## More Information

- Evidence: [`docs/evidence/0046-run-omniroute-openclaw-and-hermes-agent-on-the-vps-in-rootless-podman-with-no-lab-reach.md`](../evidence/0046-run-omniroute-openclaw-and-hermes-agent-on-the-vps-in-rootless-podman-with-no-lab-reach.md).
- Related: D-0035 (rule 2, the VPS node is never torn down), D-0036 (the box's limits), D-0038 (the secrets store), D-0041 (the pipeline), D-0042 (rule 6, the owner's taps).
