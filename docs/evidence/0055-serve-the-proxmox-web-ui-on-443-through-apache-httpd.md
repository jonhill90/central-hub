---
record: D-0055
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: on 2026-11-14 at about 12:50 UTC, role `proxmox_proxy`, its runbook, picks 224 and 234 and the register read at main ebff240; the owner's words looked up in the project decisions inbox; Apache httpd's licence and about page, `pveproxy`'s manual page, nginx's JWT module page, Caddy's reverse-proxy page and the Angie and HAProxy product pages opened
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages"
---

# Evidence for D-0055: Apache httpd for the Proxmox web UI

This file summarises the research behind D-0055. It adds nothing the research and the pages listed below did not find.

## Question

Which program should serve the Proxmox web UI on 443, now that nginx fails STD-0006, and is it in use?

## Findings

1. **The owner's words.** The project decisions inbox records his message of 2026-11-14 03:51 UTC asking never to reach anything over a non-standard port and asking why Proxmox was not on 443 [1] (sourced). Pick 224 records his yes, at 03:56:52 UTC, to a proxy on the host [2] (measured).
2. **nginx's paid side.** nginx's JWT authentication module page says the module "is available as part of our commercial subscription" [3] (sourced). The register lists nginx as `fail`, and `foss-exceptions.yaml` lists it as `pending` [2] (measured).
3. **Apache httpd.** Its licence is Apache-2.0 [4], and its about page says the server "only comes from the Apache Software Foundation, but many vendors ship their own product 'based on the Apache {Project}'" [5] (sourced). The register lists it as `pass` [2] (measured).
4. **What is built.** At main ebff240, role `proxmox_proxy` installs Debian's `apache2` packages at `2.4.71-1~deb13u1`, masked until the move; the move runs as the systemd unit `proxmox-proxy-cutover`, enables Apache httpd only after its proofs, and rolls back to nginx otherwise; no variable names the program; 8006 stays open [2] (measured).
5. **Not applied.** Pick 234 says nothing is applied, and the runbook's `last-tested` says it has not yet run on the host with Apache httpd, only against a stand-in host in CI. No workflow in `.github/workflows/` runs playbook `proxmox-proxy.yml`, so the host job the runbook needs does not exist yet [2] (measured).
6. **Caddy.** Caddy's reverse-proxy page says WebSocket connections are by default closed when the configuration is reloaded [6] (sourced).
7. **Paid editions of other proxies.** Angie's site lists Angie PRO [7], and HAProxy Technologies sells HAProxy Enterprise [8] (sourced, product pages only).
8. **`pveproxy`'s port.** Its manual page says it exposes the API "on TCP port 8006 using HTTPS", and the settings it lists for `/etc/default/pveproxy` (listen address, allow and deny lists, ciphers, compression, real-IP header and others) include no port [9] (sourced). A web search for changing its port to 443 found only Proxmox mailing-list threads from 2011 and 2012; in the 2011 one, a Proxmox developer answered that it could not be changed then [10] (sourced, old).
9. **Reach.** At main ebff240, 8 files in `hosts/` and one runbook name Apache httpd or `apache2`, and no record does. Indexes are not counted [2] (measured).

## How the decision used it

(Written from the record, not from the batch.)

Finding 1 is the context and the first driver. Findings 2 and 3 are the paywall weighing and rule 1. Finding 4 is rules 2, 3 and 5 and the exit path. Finding 5 is why the record stays proposed. Findings 6 and 7 weigh options 3 and 4, and finding 8 weighs option 5.

## Limits

- HAProxy's and Angie's paid editions were not weighed under STD-0006; only their product pages were opened.
- lighttpd, listed in pick 234's alternatives, was not checked here.
- For `pveproxy`'s port, Proxmox's bug tracker was not searched and no hands-on test was run; the claim rests on the manual page and the mailing list.
- The move has not run on the host, so the console through Apache httpd is proven only against the stand-in.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. The project decisions inbox, row for 2026-11-14 03:51 UTC, message cmsg_01X43rfNYp4H1dL1V2dkfkwN6Bf1nxMc9HHoCZ9eqA9CDr. The inbox is private; the message id is the record.
2. Repository search and code read of central-hub at ebff240 (this repository): `hosts/AGENT-PICKS.md` picks 224 and 234, `hosts/ansible/roles/proxmox_proxy/`, `docs/runbooks/serve-proxmox-on-443.md`, `docs/standards/components.yaml`, `docs/standards/foss-exceptions.yaml`.
3. nginx, "Module ngx_http_auth_jwt_module". <https://nginx.org/en/docs/http/ngx_http_auth_jwt_module.html>
4. Apache httpd LICENSE. <https://raw.githubusercontent.com/apache/httpd/trunk/LICENSE>
5. Apache httpd, ABOUT_APACHE. <https://httpd.apache.org/ABOUT_APACHE>
6. Caddy, "reverse_proxy" directive. <https://caddyserver.com/docs/caddyfile/directives/reverse_proxy>
7. Angie. <https://angie.software/en/>
8. HAProxy Technologies, "HAProxy Enterprise". <https://www.haproxy.com/products/haproxy-enterprise>
9. Proxmox VE, "pveproxy(8)". <https://pve.proxmox.com/pve-docs/pveproxy.8.html>
10. pve-user mailing list, "Can I change default port from 8006 to 443?", 2011-10-05. <https://lists.proxmox.com/pipermail/pve-user/2011-October/002504.html>

The batch is RB-0208; its working files are private.
