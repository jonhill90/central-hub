---
title: Serve the Proxmox web UI on port 443
status: draft
kind: manual
trigger: once, after the Proxmox host's certificate is set (proxmox-cert.yml); again after each certificate renewal, at least every 30 days
runner: the host job (a workflow_dispatch pipeline job on the agent box's runner, with playbooks proxmox-proxy.yml and proxmox-cert.yml on its allow list); it is not built yet, and until it exists nothing applies this playbook
outcome: the Proxmox web UI answers on https://pve.<zone> with the lab certificate, on port 443 with no port in the address, served by Apache httpd; port 80 redirects to it; port 8006 stays as the fallback and the agent box's lifeline
needs: the host's certificate from the lab CA (role proxmox_cert, playbook proxmox-cert.yml) with a DNS name for the host's web UI that resolves from where the owner browses; the host firewall rows for 443 and 80 (the same sources as 8006); the host job and its box limits (an SSH key on the box used only through a root-owned wrapper, tcp 22 on the lifeline), which need the owner's tap
private-values: [proxmox-cert-names]
files: [hosts/ansible/roles/proxmox_proxy/, hosts/ansible/playbooks/proxmox-proxy.yml, hosts/ansible/roles/proxmox_firewall/defaults/main.yml, .github/hosts-check/tests/test_proxy.sh]
last-tested: "not yet run on the host with Apache httpd; the role was tested on 2026-11-14 against a stand-in Proxmox host in a container (Debian trixie, systemd, nginx serving as the old role left it, a stand-in pveproxy): the install with nginx still serving, the move, a failing proof, a stopped move, a killed run, an open console across a graceful reload, and a host with no nginx (.github/hosts-check/tests/test_proxy.sh)"
superseded-by:
---

# Serve the Proxmox web UI on port 443

## Why

The owner's rule, 2026-11-14 at 03:51 UTC: no non-standard ports for any lab web page. The Proxmox web UI listens on 8006 (`pveproxy`), so a reverse proxy on the host answers on 443 and passes everything to it on `127.0.0.1:8006`. Proxmox's own wiki gives this shape with nginx, [Web Interface Via Nginx Proxy](https://pve.proxmox.com/wiki/Web_Interface_Via_Nginx_Proxy), tested only to Proxmox VE 6.3; this host runs 9, so the role ends with its own proof.

The proxy is Apache httpd, not nginx. nginx's owner sells a commercial build that holds modules back, such as JWT authentication ([ngx_http_auth_jwt_module](https://nginx.org/en/docs/http/ngx_http_auth_jwt_module.html), "available as part of our commercial subscription"), so nginx fails STD-0006 test 2. Apache httpd is licensed under the [Apache License 2.0](https://raw.githubusercontent.com/apache/httpd/trunk/LICENSE), and the project's own page says the server "only comes from the Apache Software Foundation" and leaves paid modules and support to other companies ([ABOUT_APACHE](https://httpd.apache.org/ABOUT_APACHE)). It tunnels the console's WebSocket with `ProxyPass ... upgrade=websocket` (2.4.47 and later, [mod_proxy](https://httpd.apache.org/docs/2.4/mod/mod_proxy.html)), and a graceful restart lets each child finish its current request ([stopping](https://httpd.apache.org/docs/2.4/stopping.html)), so a certificate reload does not cut an open console.

Port 8006 is not closed. It stays as the fallback if the proxy fails, and it is the route the agent box's lifeline uses to reach the Proxmox API ([lifeline runbook](set-up-the-box-lifeline.md)).

## What is built

- Role `proxmox_proxy` (renamed from `proxmox_nginx`; no variable names the program, so a later swap changes only the role's insides):
  - Debian's `apache2`, `apache2-bin`, `apache2-data` and `apache2-utils` at one pinned version (`proxmox_proxy_apache_version`, the trixie-security build when read, 2026-11-14), installed without ever starting: Debian's postinst starts apache2 on port 80, which nginx holds until the move. Before apt runs, the role masks `apache2.service` and writes a `/usr/sbin/policy-rc.d` that denies every service start (exit 101); after apt it removes that file and runs `systemctl disable apache2`, because a mask does not remove the enable links the postinst makes.
  - Modules `ssl`, `proxy` and `proxy_http`; the packaged default site off; `/etc/apache2/sites-available/proxmox.conf` with a `*:80` VirtualHost that redirects to the first name and a `*:443` VirtualHost that serves the certificate `pvenode cert set` wrote (`/etc/pve/local/pveproxy-ssl.pem` and `.key`, so the lab CA chain is the same on 443 and 8006) and passes everything to `pveproxy` with `upgrade=websocket`, `flushpackets=on`, a one-hour timeout and no body limit.
  - A systemd drop-in so `apache2.service` requires and starts after `pve-cluster.service`, because the certificate lives in `/etc/pve`.
  - Two scripts in `/usr/local/libexec/`: `proxy-proofs.sh` (front page 200, API 401, a WebSocket upgrade answered 401 by `pveproxy`, port 80 answering 301 to the first name, all over 127.0.0.1 with the served name and the CA bundle checked) and `proxy-cutover.sh` (the move, below).
- The move from nginx, once per host. The role starts `proxy-cutover.sh` with `systemd-run` as its own unit, `proxmox-proxy-cutover`, so a dropped SSH connection, a killed `ansible-playbook` or a cancelled pipeline job does not stop it half-way. The script stops nginx, starts Apache httpd and runs the proofs; only then does it enable apache2 and disable nginx. A failed proof or a stop of the unit runs its rollback: apache2 stopped and masked, nginx started. A reboot part-way brings nginx back, because apache2 is enabled only at the end. It writes `done`, `rolled-back` or `started` to `/var/lib/proxmox-proxy/cutover.result`. A host built fresh, with no nginx, gets the same move without the nginx steps.
- Host firewall (role `proxmox_firewall`): tcp 443 and 80 from IPSet `management`, the same sources as 22 and 8006. The swap changes no port and no source.
- The test: `.github/hosts-check/tests/test_proxy.sh` (CI job `proxy`), against a stand-in host in a container, `.github/hosts-check/proxy/`.

## What the owner decides

- **The host job.** The playbook reaches the host over SSH as root, and the agent box has no SSH key for the host and reaches it on 8006 only. The host job needs a key on the box, a root-owned wrapper with a fixed playbook allow list, and tcp 22 on the lifeline; those are box limits, so they need the owner's tap. Root on the Proxmox host reaches every guest, VM 258 and CT 259 included. If the host firewall refuses 22 from the lifeline address, that is a separate firewall tap.
- **The DNS name.** `proxmox_proxy_server_names` is the same list as `proxmox_cert_names`, set in the private inventory. The first name is where port 80 redirects.

## Steps (through the host job)

1. Check run: the host job with playbook `proxmox-proxy.yml`. It runs `--check --diff` first.
   On a host without Apache httpd, the check run shows the files it would write and says it skips the configuration test, the move and the proof, because apt installs nothing in check mode.
   expect: the diff shows the site, the drop-in, the two scripts and `proofs.env`, and nothing under `/etc/nginx/`.

2. The run: the same job, without the check.
   expect: `failed=0`; the task "The move, with its proofs" is `changed`; `/var/lib/proxmox-proxy/cutover.result` starts with `done`; `ss -ltnp 'sport = :443'` names `apache2`; the last task, "The proof holds", passes.
   If the move rolls back, nginx serves again and the run fails with the unit's error. Read `journalctl -u proxmox-proxy-cutover`, fix the cause, remove `cutover.result`, and run again; a re-run does not move a host whose file says `rolled-back` or `started`.

3. Open the address from the owner's device: `https://pve.<zone>`.
   expect: the login page with no certificate warning and no port in the address. Open a VM's console (noVNC) and a node shell: both must connect. This is the part no check in the role can prove, because a console needs a login ticket.

4. After each certificate renewal (`proxmox-cert.yml`), run `proxmox-proxy.yml` again.
   why: Apache httpd reads the certificate at a reload; the role reloads it gracefully when the certificate it serves is not the one on disk.
   expect: the role's reload task shows `changed` only after a renewal.

To install Apache httpd and leave nginx serving, set `proxmox_proxy_cutover: false`.

## If it fails

- Apache httpd does not start after a reboot: `systemctl status apache2` and `journalctl -u apache2`. The drop-in makes it wait for `pve-cluster`; if `/etc/pve` is not mounted, fix that first. The web UI is still on 8006.
- The browser shows a certificate warning: the name is not in the certificate (`proxmox_cert_names`), or the device does not trust the lab root.
- The console opens and closes at once, or shows a blank pane: the upgrade is not reaching `pveproxy`. Check `/etc/apache2/sites-available/proxmox.conf` for `upgrade=websocket` on the `ProxyPass` line, and that nothing else (a second proxy) sits in front.
- `443 times out from the browser`: the host firewall rows for 443 and 80 are not in.

## Exit

To go back to nginx on a moved host: `systemctl disable --now apache2`, `systemctl mask apache2`, `systemctl enable --now nginx` (nginx stays installed until the clean-up after the move). To serve on 8006 only: `systemctl disable --now apache2`, take the 443 and 80 rows out of `proxmox_firewall_rules`, then run the firewall role. Another proxy (Caddy, Apache-2.0) replaces only the role's insides.
