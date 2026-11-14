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
revisit-when: the owner answers whether to keep the stopgap or start the move off it now; a research batch tests Headscale on the features the lab uses; the lab needs a feature that Tailscale keeps in a paid plan; the free plan's terms change; the agents get accounts of their own (D-0030) and need their own identities on the network; or the lab is built for real, when the owner is asked again, as his card of 2026-11-10 and the Tailscale entry in `docs/standards/foss-exceptions.yaml` say
---

# Keep Tailscale as a swappable stopgap for reaching the lab from outside, with Headscale as the way off its closed coordination server

## Context and Problem Statement

The owner, his Mac and the agents reach the lab from outside through Tailscale: a tailnet connector container on the Proxmox host routes to the lab's networks, and the agent box joins as a tagged device (`hosts/terraform/home/tailnet/`, `tailnet-policy/`, `remote-access/`, roles `tailnet_connector` and `agent_box`). 30 files in `hosts/`, 11 runbooks, D-0036 and STD-0002 build on it. No decision record chose it.

Tailscale's client is open source, but its coordination server is closed, and its paid plans hold features back (evidence finding 3). Between 04:43:45 and 04:44:57 UTC on 2026-11-14 the owner ruled that nothing in the lab may come from an owner who holds a feature back behind a paid tier (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, and most plainly cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4), as D-0040 records, and STD-0006 test 2 now says the same. **Tailscale fails that ruling and that test.**

The only owner answer for keeping it is older than the ruling. On 2026-11-10 a decision card (cmsg_01X43rfNYp4H1dL1V2dkfkwN94SWGX6ssfCizqji4VUhLp, the question) asked whether Tailscale was acceptable for now under his rule of FOSS and no lock-in, and offered three answers: keep it for now and keep it swappable, plan the move off it now, or drop the rule. He tapped the first at 19:09 UTC. `docs/standards/foss-exceptions.yaml` line 16 records that answer: state `kept`, "as long as it stays swappable and nothing new depends on it in a way that can't be swapped", "asked again before the lab is built for real". That file was added with STD-0006 by #277 at 06:31 UTC on 2026-11-14 and accepted by #281, both after the ruling, but both were written and approved by agents; the owner has said nothing about Tailscale since the ruling.

Keeping it or moving off it is a change to the tailnet, which stays behind the owner's words (D-0036 rule 8). So this record does not settle it. It writes down the stopgap, what keeps it swappable, the way off, and the question he is asked.

## Decision Drivers

- **FOSS with no paid feature in use** (REQ-0032; the owner, 2026-11-14).
- **Swappable** (the owner's card, 2026-11-10 19:09 UTC; CLAUDE.md rule 6).
- **Reach the lab without opening ports to the internet.**
- **Agents rebuild the lab from the box** (D-0035, D-0036), so the box's way in must survive a rebuild.

## Considered Options

1. **Keep Tailscale on its free plan** as a stopgap, with nothing in the lab that only Tailscale can hold.
2. **Headscale**, a self-hosted coordination server for the same open-source clients.
3. **NetBird**, self-hosted.

## Decision Outcome

Proposed: **option 1, as a stopgap**, the owner's answer of 2026-11-10, until he answers the question below. Option 2 is the named way off: it keeps the same clients, Headscale's documentation says it implements the same policy ACLs as Tailscale, written in HuJSON, and no paid edition of it was found (evidence finding 6). Option 3 is not a way off: NetBird holds features back from its self-hosted community edition (evidence finding 7), so it fails STD-0006 test 2 as Tailscale does. These readings come from documentation and searches, not from a test.

### Keep it now, or plan the move off it now

The 2026-11-10 card offered both. They weigh as follows.

| | Keep it now (option 1) | Plan the move off it now (option 2) |
|---|---|---|
| The 2026-11-14 ruling | Broken until the move | Kept once the move is done |
| How the owner, his Mac and the agents reach the lab | No change | Changes once, on the path everyone uses to reach the lab |
| Work it needs first | None | A research batch that runs Headscale on a dev VM and replays the policy file; a VM and its backup |
| Risk | The lab depends on one company's closed server | A move that hasn't been tested could cut off the way in; rule 5's lifeline and break-glass cover that |

The agents' pick is to **plan the move now and keep Tailscale until the test passes**: the research batch and the dev-VM test change nothing on the live tailnet, and the cut-over itself is the tailnet change the owner decides. The owner is asked once, on a decision card, whether to keep the stopgap as it is or to have the move planned now. His answer is written into this record, in its pull request if it comes first, or later by a correction under D-0006.

Diagram: not applicable. One component is chosen, and its place in the network is drawn in STD-0002 and the remote-access runbooks.

### Rules

1. **Licence and edition.** The Tailscale client and daemon are BSD-3-Clause. The coordination server is Tailscale's closed service. The lab stays on the free Personal plan. Which plan the tailnet is on now has not been read; the first check under Confirmation reads it.
2. **No paid feature.** The lab must not start to use a feature of a paid plan (among them SCIM, device posture, more users than the free plan allows). Which features the tailnet uses now has not been measured; the same check reads them.
3. **Policy in code.** The tailnet policy and the connector are in `hosts/terraform/home/tailnet-policy/` and `tailnet/`, so they can be read and replayed into another coordination server.
4. **Nothing only Tailscale can hold.** No secret, address plan or identity lives only in Tailscale. Addresses come from STD-0002; identities from the lab's own identity provider where it applies.
5. **Ways in that don't need it.** The agent box keeps its lifeline to the Proxmox host (`set-up-the-box-lifeline.md`), and break-glass access stays as in `use-break-glass-access.md`.

### Consequences

- Good: no change to how anyone reaches the lab today.
- Good: the policy is code, so a move to Headscale replays it.
- Bad: the coordination server is closed and run by one company; the lab depends on it until the move.
- Bad: until the move, the lab keeps a piece that fails the 2026-11-14 ruling and STD-0006 test 2.
- Bad: the stopgap has no end date.

### Confirmation

- A pipeline run (D-0041) reads the tailnet's plan and the features in use, and its log is the measurement for rules 1 and 2.
- Every tailnet setting the lab relies on is in `hosts/terraform/home/tailnet*` or the remote-access code.
- A reviewing agent checks every remote-access change against rule 2.

### Exit path

Run Headscale (BSD-3-Clause) on a lab VM, point the same Tailscale clients at it with `--login-server`, and replay the policy file. NetBird is not an exit, because it holds features back too (option 3). Headscale serves a single tailnet, which is all the lab has.

## Pros and Cons of the Options

### Option 1: Tailscale free plan

- Good: running and documented; clients are open source.
- Bad: closed coordination server; paid plans hold features back.

### Option 2: Headscale

- Good: BSD-3-Clause; same clients; its documentation says it implements Tailscale's policy ACLs, adapted to self-hosting.
- Good: no paid edition was found: its FAQ says it is "not enterprise software" and serves homelabbers and self-hosters, and searches of the web, its issues and its code turned up none. No hands-on check was run, so this is not proof that none exists.
- Bad: its coverage of the Tailscale features the lab uses was not checked; one more server to run and back up.

### Option 3: NetBird

- Good: client BSD-3-Clause; its management, signal and relay servers are AGPL, a copyleft licence, which is FOSS under REQ-0032; self-hostable.
- Bad: open core. Its Enterprise Commercial License unlocks, for self-hosters, active-active high availability, SCIM, EDR and MDM integrations, traffic-flow logging, peer approval and audit event streaming, so it fails STD-0006 test 2.
- Bad: new clients and a new policy model.

## More Information

- Evidence: [`docs/evidence/0043-keep-tailscale-as-a-swappable-stopgap-for-reaching-the-lab.md`](../evidence/0043-keep-tailscale-as-a-swappable-stopgap-for-reaching-the-lab.md).
