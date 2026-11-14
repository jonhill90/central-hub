---
id: D-0043
title: Keep Tailscale as a swappable stopgap for reaching the lab from outside, with Headscale as the way off its closed coordination server
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: a research batch compares self-hosted coordination servers (Headscale, NetBird) on the features the lab uses; the lab needs a feature that Tailscale keeps in a paid plan; the free plan's terms change; or the agents get accounts of their own (D-0030) and need their own identities on the network
---

# Keep Tailscale as a swappable stopgap for reaching the lab from outside, with Headscale as the way off its closed coordination server

## Context and Problem Statement

The owner, his Mac and the agents reach the lab from outside through Tailscale: a tailnet connector container on the Proxmox host routes to the lab's networks, and the agent box joins as a tagged device (`hosts/terraform/home/tailnet/`, `tailnet-policy/`, `remote-access/`, roles `tailnet_connector` and `agent_box`). 30 files in `hosts/`, 11 runbooks, D-0036 and STD-0002 build on it. No decision record chose it.

Tailscale's client is open source, but its coordination server is closed, and its paid plans hold features back. On 2026-11-10 the owner answered on a decision card that Tailscale is fine for now and must stay swappable. On 2026-11-14 he ruled that no piece of the lab may be open core. This record writes down the stopgap, what keeps it swappable, and the way off.

## Decision Drivers

- **FOSS with no paid feature in use** (REQ-0032; the owner, 2026-11-14).
- **Swappable** (the owner, 2026-11-10; CLAUDE.md rule 6).
- **Reach the lab without opening ports to the internet.**
- **Agents rebuild the lab from the box** (D-0035, D-0036), so the box's way in must survive a rebuild.

## Considered Options

1. **Keep Tailscale on its free plan** as a stopgap, with nothing in the lab that only Tailscale can hold.
2. **Headscale**, a self-hosted coordination server for the same open-source clients.
3. **NetBird**, self-hosted.

## Decision Outcome

Proposed: **option 1, as a stopgap**, the owner's answer of 2026-11-10. Option 2 is the named way off, because it keeps the same clients and the same policy format. Option 3 changes clients and policy. Neither has been compared on fit by a research batch.

Diagram: not applicable. One component is chosen, and its place in the network is drawn in STD-0002 and the remote-access runbooks.

### Rules

1. **Licence and edition.** The Tailscale client and daemon are BSD-3-Clause. The coordination server is Tailscale's closed service, on the free Personal plan.
2. **No paid feature.** The lab uses no feature of a paid plan (among them SCIM, device posture, more than the free plan's users).
3. **Policy in code.** The tailnet policy and the connector are in `hosts/terraform/home/tailnet-policy/` and `tailnet/`, so they can be read and replayed into another coordination server.
4. **Nothing only Tailscale can hold.** No secret, address plan or identity lives only in Tailscale. Addresses come from STD-0002; identities from the lab's own identity provider where it applies.
5. **Ways in that don't need it.** The agent box keeps its lifeline to the Proxmox host (`set-up-the-box-lifeline.md`), and break-glass access stays as in `use-break-glass-access.md`.

### Consequences

- Good: no change to how anyone reaches the lab today.
- Good: the policy is code, so a move to Headscale replays it.
- Bad: the coordination server is closed and run by one company; the lab depends on it until the move.
- Bad: the stopgap has no end date.

### Confirmation

- Every tailnet setting the lab relies on is in `hosts/terraform/home/tailnet*` or the remote-access code.
- A reviewing agent checks every remote-access change against rule 2.

### Exit path

Run Headscale (BSD-3-Clause) on a lab VM, point the same Tailscale clients at it with `--login-server`, and replay the policy file. NetBird is the second path, with its own clients.

## Pros and Cons of the Options

### Option 1: Tailscale free plan

- Good: running and documented; clients are open source.
- Bad: closed coordination server; paid plans hold features back.

### Option 2: Headscale

- Good: BSD-3-Clause; same clients.
- Bad: its paid side and its coverage of Tailscale's features were not checked; one more server to run and back up.

### Option 3: NetBird

- Good: client BSD-3-Clause; self-hostable.
- Bad: its management, signal and relay servers are under another licence (AGPL, per its LICENSE file); paid cloud tiers not checked; new clients and policy.

## More Information

- Evidence: [`docs/evidence/0043-keep-tailscale-as-a-swappable-stopgap-for-reaching-the-lab.md`](../evidence/0043-keep-tailscale-as-a-swappable-stopgap-for-reaching-the-lab.md).
