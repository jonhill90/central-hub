---
id: D-0055
title: Serve the Proxmox web UI on 443 through Debian's Apache httpd in place of nginx, with port 8006 kept as the fallback
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: the move from nginx has run on the host (then this record can be accepted); Proxmox serves its own web UI on 443; sign-in to Proxmox needs a proxy feature Apache httpd lacks; or Apache httpd's licence or Debian's packaging changes
---

# Serve the Proxmox web UI on 443 through Debian's Apache httpd in place of nginx, with port 8006 kept as the fallback

## Context and Problem Statement

On 2026-11-14 at 03:51 UTC the owner asked never to reach anything over a non-standard port, and asked why Proxmox was not on 443 (cmsg_01X43rfNYp4H1dL1V2dkfkwN6Bf1nxMc9HHoCZ9eqA9CDr). A few minutes later he said yes to a proxy on the host, as agent pick 224 records. Proxmox's own server, `pveproxy`, listens on 8006, so a reverse proxy on the host answers on 443 and passes everything to it on `127.0.0.1:8006` (runbook [serve-proxmox-on-443.md](../runbooks/serve-proxmox-on-443.md)).

The first proxy was Debian's nginx. Between 04:43:45 and 04:44:57 UTC the same day the owner ruled that no piece of the lab may hold something back behind a paywall (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). nginx's company keeps modules such as JWT authentication in its commercial build, so nginx fails STD-0006 rule 2, and the register lists it as `fail` with a `pending` exception. PR #336 rebuilt the role as `proxmox_proxy` with Apache httpd (agent pick 234). No decision record chose either program.

Nothing is applied yet. The move waits for the host job on the agent box, whose SSH key, wrapper, playbook allow list and tcp 22 on the lifeline are box limits (pick 234; the runbook's "What the owner decides").

## Decision Drivers

- **Web pages by name on 443** (the owner, 2026-11-14 03:51 UTC).
- **FOSS with nothing held back behind a paywall** (REQ-0032; the owner, 2026-11-14; STD-0006 rule 2).
- **The console must work:** the proxy tunnels WebSockets and does not cut an open console when the certificate reloads.
- **Few moving parts on the hypervisor:** a package from the host's own distribution, updated with it.
- **Replaceable** (CLAUDE.md rule 6).

## Considered Options

1. **Debian's Apache httpd.**
2. **Keep Debian's nginx.**
3. **Caddy.**
4. **HAProxy or Angie.**
5. **`pveproxy` on 443 itself.**

## Decision Outcome

Proposed: **option 1**, as pick 234 and PR #336 built it.

- nginx (option 2) fails STD-0006 rule 2.
- Caddy (option 3) is Apache-2.0, but by default it closes open WebSocket connections when its configuration reloads, which would cut an open console at each certificate renewal.
- HAProxy and Angie (option 4) each have a paid edition (HAProxy Enterprise, Angie PRO), which STD-0006 would have to weigh first.
- `pveproxy` offers no setting for its port: its manual page gives TCP port 8006, and the settings it reads from `/etc/default/pveproxy` name none. So option 5 is out.

This record stays `proposed`. The agents accept a record under D-0042 rule 3 only for a piece already in use (an agent pick of 2026-11-14 09:31 UTC), and Apache httpd does not serve the host until the move runs. Once the move has run and the runbook's step 3 shows the console working, a later PR can accept it.

Diagram: not applicable. One proxy in front of one server on the same host.

### Rules

1. **Licence and source.** Apache httpd, Apache-2.0, from Debian's own repositories at one pinned version (`proxmox_proxy_apache_version`), with the four `apache2` packages pinned together.
2. **One move, with a way back.** The move from nginx runs once, as its own systemd unit, and enables Apache httpd only after its proofs pass. A failed proof or a stop rolls back to nginx. nginx stays installed and disabled until the runbook's step 5 purges it, and only then do its register row and exception go (STD-0006 rule 5).
3. **Fallback.** Port 8006 stays open to the management set, as the fallback and the agent box's lifeline.
4. **Sign-in is not the proxy's job.** Sign-in to Proxmox goes through Proxmox's own OpenID Connect realm (D-0037), not through the proxy.
5. **No program in the variables.** No role variable names the program, so a later swap changes only the role's insides.

### Consequences

- Good: the web UI by name on 443 from one Debian package, with no paid edition behind it.
- Good: the console's WebSocket is tunnelled, and a graceful reload lets open requests finish, so a certificate renewal does not cut it.
- Bad: one more service on the hypervisor to patch.
- Bad: until the move runs, nginx serves 443 and STD-0006 still counts it as a pending fail.

### Confirmation

- After the move, `/var/lib/proxmox-proxy/cutover.result` starts with `done`, `ss -ltnp 'sport = :443'` names `apache2`, and the runbook's step 3 opens a console through 443.
- CI job `proxy` (`.github/hosts-check/tests/test_proxy.sh`) passes against the stand-in host.

### Exit path

The role holds a listener, a certificate path and one upstream, and no variable names the program, so Caddy (Apache-2.0) or another proxy replaces only the role's insides. Turning the proxy off leaves Proxmox on 8006, as before (the runbook's Exit).

## Pros and Cons of the Options

### Option 1: Debian's Apache httpd

- Good: Apache-2.0; no paid edition from its maker; from the host's own distribution; tunnels WebSockets; graceful reload.
- Bad: not yet run on the host.

### Option 2: keep Debian's nginx

- Good: running today.
- Bad: fails STD-0006 rule 2.

### Option 3: Caddy

- Good: Apache-2.0.
- Bad: closes open WebSockets on a config reload by default.

### Option 4: HAProxy or Angie

- Good: widely used as proxies.
- Bad: each has a paid edition, not weighed under STD-0006.

### Option 5: `pveproxy` on 443

- Good: nothing extra on the host.
- Bad: `pveproxy` offers no setting for its port.

## More Information

- Evidence: [`docs/evidence/0055-serve-the-proxmox-web-ui-on-443-through-apache-httpd.md`](../evidence/0055-serve-the-proxmox-web-ui-on-443-through-apache-httpd.md).
- Related: D-0037 (sign-in to Proxmox), D-0042 (when agents may accept), STD-0006 and its register (`docs/standards/components.yaml`), runbook [serve-proxmox-on-443.md](../runbooks/serve-proxmox-on-443.md).
