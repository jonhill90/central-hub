---
id: D-0060
title: Let the VPS host a rebuild login that reaches the lab through its own tailnet node, so the lab can be rebuilt when Proxmox is down, and keep the apps cut off
status: proposed
date: 2026-11-18
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0035, D-0042, D-0043, D-0046]
supersedes: []
superseded-by:
revisit-when: the lab gets a second always-on host outside Proxmox that agents can rebuild from; the agents get a hardware or out-of-band reach to the Proxmox host; tailscale is replaced (D-0043); or an app on the VPS needs lab reach
---

# Let the VPS host a rebuild login that reaches the lab through its own tailnet node, so the lab can be rebuilt when Proxmox is down, and keep the apps cut off

## Context and Problem Statement

At 06:04:55 UTC on 2026-11-18 the owner said the VPS is a second jump box: it hosts the lab's own apps (OmniRoute, OpenClaw, Hermes Agent), and if the Proxmox host went down it would be the agents' other route in to rebuild it (cmsg_01X43rfNYp4H1dL1V2dkfkwNXDyf8bn8y8AKU2K7JFBKhu).

D-0046 rule 3 gives `tag:vps` no grant into the lab, so the VPS cannot do that. Two more facts decide the shape:

- The lab's only tailnet route is the connector CT 900, a container on the Proxmox host (`docs/runbooks/set-up-tailnet-client-in-ct-900.md`). When Proxmox is down, CT 900 is down, so no tailnet route to the lab exists, from the VPS or from anywhere. The agent box (VM 258) and the firewall (VM 100) run on the same host and go down with it.
- The apps read untrusted messages and run tools (D-0046 context). They must stay cut off from the lab.

## Decision Drivers

- **The owner's ask**: a jump box that can rebuild Proxmox when it is down.
- **The apps stay cut off from the lab.**
- **A route that does not depend on the host being rebuilt.**
- **Agents act alone on Proxmox** (the owner's orders of 2026-11-18 01:14:19 UTC, cmsg_01X43rfNYp4H1dL1V2dkfkwNJrgu7NtnDqTkDB6rd3RUS2, and 01:27:47 UTC, cmsg_01X43rfNYp4H1dL1V2dkfkwN1fjfHhrXjKbRQiLpvrViV5: no clicks; every action by API or CLI).
- **No secret in this public repository, and no money or access right taken by an agent pick** (D-0042 rule 6).

## Considered Options

1. **A second tailnet node on the VPS, tagged for rebuild only, run by its own Linux user; the lab route comes from a connector on an always-on device that does not depend on Proxmox.**
2. **Give `tag:vps` the lab route** (reverse D-0046 rule 3 whole).
3. **No lab reach from the VPS**; rebuild only from the agent box and cloud sessions, as now.

## Decision Outcome

Proposed: **option 1**. Every rule below is an agent pick unless it cites the owner.

### Rules

1. **Rule 3 of D-0046 stays for `tag:vps` and the app users.** This record adds one new thing beside it and removes nothing from it.
2. **One more tailnet node on the VPS, `tag:rebuild-jump`.** A second `tailscaled` runs in userspace-networking mode as Linux user `rebuild`, with its own state folder and a control socket (`--socket`) that only `rebuild` (and root) can open. Its SOCKS5 or HTTP proxy is not used or not started: those listen on TCP that any local user can open, so the apps' users could ride the node. The only path is `tailscale --socket=<that socket> nc <host> <port>` run by `rebuild`, which goes through the socket's file permissions. It is not the host's own node, so the apps and every other user keep the identity `tag:vps` and still reach nothing in the lab. Only `tag:rebuild-jump` gets a grant: tcp:22 to the Proxmox host's management address and to the lab connector's route. (Grants name the node's tag; the SSH rule of rule 5 names the host's own node, `tag:vps`, because Tailscale SSH is served by the host's node and the local user, `rebuild`, picks who may sign in.)
3. **A route that survives Proxmox down.** The lab needs a tailnet connector (or the host's own management address on a route) on an always-on device that is not on Proxmox, on the same management network as the Proxmox host. This record does not pick the device: if no such device is already in the lab, buying one is money (D-0042 rule 6), and goes on its own card. Until it exists, option 1 gives no more than today's route through CT 900, and the VPS still cannot rebuild a host that is off.
4. **How the host's agent keys are held.** `rebuild` makes its own SSH key pair on the VPS; the private key never leaves the VPS, never goes in the repository or a message, and is mode 600 in `rebuild`'s home. The public key is installed on the Proxmox host as an account of its own for the agents, by the pipeline. The account's rights are an agent pick here, and granting them on the Proxmox host is an access right, so it is the owner's tap (D-0042 rule 6); the owner's orders of 01:14:19 and 01:27:47 UTC (above) say only that agents act on Proxmox without the web page and without him, not which account or rights. Which agent sessions may use the key is set by the tailnet's SSH rule of rule 5 (`dst: tag:vps`, user `rebuild`), not by a copy of the key.
5. **Who may sign in as `rebuild`.** `tag:agent` (cloud sessions) and the owner (`autogroup:admin`), by an SSH rule with `dst: tag:vps` and `users: ["rebuild"]`. Not `tag:agent-box`, not `deploy`, and no app user. Today `policy.hujson.tftpl` gives `tag:github-actions` `autogroup:nonroot` on `tag:vps` (line 86 on main at 211fcfc), and `tag:agent` too, so `rebuild` would be open to CI runners; the tailnet change of rule 7(c) must therefore also (a) remove `tag:github-actions`'s SSH rule to `tag:vps`, which D-0046 S1 already does, and (b) replace `autogroup:nonroot` for `tag:agent` with named users. An `sshTests` entry denies `rebuild` to `tag:github-actions`, `tag:agent-box` and every other tag. This is an access right and the tailnet change is the owner's tap, as D-0042 rule 6 keeps (rule 7).
6. **Policy tests.** The tailnet policy's tests deny `tag:vps` and the node of every app user any lab address, and accept `tag:rebuild-jump` only to the Proxmox host's management address and the connector's route.
7. **Order, each step its own pipeline job and, where D-0042 rule 6 says, its own card.** (a) This record accepted; (b) the always-on connector device named, with a card if it costs money; (c) after D-0046's S1 has applied, a tailnet apply adding `tag:rebuild-jump`, its grants, its SSH rule and the policy tests, one card naming the saved plan and commit (D-0036 rule 8); (d) the host role adds user `rebuild` and its `tailscaled`; (e) a secrets step: the node's auth key goes in OpenBao and onto the VPS, one card (D-0042 rule 6); (f) the proof: a rebuild drill from the VPS against the dev VNet first, then a real "Proxmox host down" drill with the connector device up.
8. **It is break-glass for the Activation gate.** This path is recorded as the break-glass reach (central-hub Activation gate, item 7) once step (f) passes.

### Consequences

- Good: a Proxmox outage no longer ends the agents' reach, once rule 3's device exists.
- Good: the internet-facing apps stay cut off; the grant belongs to a node only `rebuild` can use.
- Bad: root on the VPS can use both nodes. Until S4 of D-0046 lands, every agent session is root there. So step (c) waits for D-0046's S1 and S4, or the apps and the lab route share a root.
- Bad: one more secret (the node's auth key) and one more key (the host SSH key) live on a public-internet VPS.
- Bad: rule 3's device is a new always-on machine to build and keep; without it the record gives nothing for the "Proxmox is down" case.
- Bad: a second `tailscaled` in userspace mode is vendor-documented but not yet tested on this VPS; step (f) is the test.
- Neutral: the VPS's own firewall stays the owner's call, as in D-0046.

### Confirmation

- The policy tests of rule 6 pass on every tailnet apply.
- From the VPS, as `rebuild`, the Proxmox host's SSH answers; as `omniroute`, `openclaw`, `hermes` and `deploy`, it does not, including by any local TCP proxy port.
- A sign-in as `rebuild` from `tag:github-actions` is refused by an `sshTests` entry.
- The dev-VNet rebuild drill and the "host down" drill of rule 7(f) are logged.

## Pros and Cons of the Options

### Option 2: give `tag:vps` the lab route

- Good: no second node.
- Bad: the apps that read untrusted messages would reach the lab. D-0046 rule 3 exists to prevent that.

### Option 3: no lab reach from the VPS

- Good: nothing new to secure.
- Bad: it does not do what the owner asked; a Proxmox outage leaves no agent route to the lab at all.

## More Information

- Evidence: [`docs/evidence/0060-let-the-vps-host-a-rebuild-login-that-reaches-the-lab-through-its-own-tailnet-node.md`](../evidence/0060-let-the-vps-host-a-rebuild-login-that-reaches-the-lab-through-its-own-tailnet-node.md).
- Amends D-0046 rule 3 by adding to it. Related: D-0035 (the lab is torn down and rebuilt by agents; rule 2, the VPS node is never torn down), D-0042 rule 6 (the owner's taps), D-0043 (tailscale is a swappable stopgap).
