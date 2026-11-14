---
title: Serve the Proxmox web UI on port 443
status: draft
kind: manual
trigger: once, after the Proxmox host's certificate is set (proxmox-cert.yml); again after each certificate renewal, at least every 30 days
runner: the owner's Mac (a person), through the controller's Ansible, after the owner's go on the host firewall change
outcome: the Proxmox web UI answers on https://pve.<zone> with the lab certificate, on port 443 with no port in the address; port 80 redirects to it; port 8006 stays as the fallback and the agent box's lifeline
needs: the host's certificate from the lab CA (role proxmox_cert, playbook proxmox-cert.yml) with a DNS name for the host's web UI that resolves from where the owner browses; the owner's typed go on the host firewall change (443 and 80 from the same sources as 8006)
private-values: [proxmox-cert-names]
files: [hosts/ansible/roles/proxmox_nginx/, hosts/ansible/playbooks/proxmox-nginx.yml, hosts/ansible/roles/proxmox_firewall/defaults/main.yml]
last-tested: "not yet run on the host; the proxy rules were tested against a stand-in pveproxy on 2026-11-14 (front page 200, API 401, a WebSocket request reaching it with Upgrade websocket, port 80 redirecting)"
superseded-by:
---

# Serve the Proxmox web UI on port 443

## Why

The owner's rule, 2026-11-14 at 03:51 UTC: no non-standard ports for any lab web page. The Proxmox web UI listens on 8006 (`pveproxy`), so nginx on the host answers on 443 and passes everything to it on `127.0.0.1:8006`. The shape is Proxmox's own wiki page, [Web Interface Via Nginx Proxy](https://pve.proxmox.com/wiki/Web_Interface_Via_Nginx_Proxy), which was tested only to Proxmox VE 6.3; this host runs 9, so the role ends with its own proof.

Port 8006 is not closed. It stays as the fallback if nginx fails, and it is the route the agent box's lifeline uses to reach the Proxmox API ([lifeline runbook](set-up-the-box-lifeline.md)).

## What is built

- Role `proxmox_nginx`: Debian's `nginx` and `nginx-common` at one pinned version (the newest in trixie-security when read, 2026-11-14), `/etc/nginx/conf.d/proxmox.conf` with a 443 server that proxies to `pveproxy` (HTTP/1.1, `Upgrade` and `Connection` headers for the noVNC console, proxy buffering off, one-hour timeouts) and a port 80 server that redirects to the first name, and the packaged default site switched off.
- The certificate is the one `pvenode cert set` already wrote for the web UI (`/etc/pve/local/pveproxy-ssl.pem` and `.key`), so the lab CA chain is the same on 443 and 8006.
- A systemd drop-in so `nginx.service` requires and starts after `pve-cluster.service`, because those files live in `/etc/pve`.
- Host firewall (role `proxmox_firewall`): tcp 443 and 80 from IPSet `management`, the same sources as 22 and 8006.

## What the owner decides

- **The host firewall rule.** Opening 443 and 80 is a firewall change, so it needs the owner's typed words, naming the pull request and its head. Until the firewall role runs with the two new rows, nginx is up but the host drops 443 and 80.
- **The DNS name.** `proxmox_nginx_server_names` is the same list as `proxmox_cert_names`, set in the private inventory. The first name is where port 80 redirects.

## Steps (after the owner's go)

1. Open the firewall: run the firewall role as its README says (the switch stays on; it arms the dead-man timer first): `ansible-playbook -i inventories/home/ playbooks/proxmox-safety.yml --tags firewall -e '{"proxmox_firewall_enable": true}'`.
   expect: the role's own checks pass, and `pve-firewall compile` lists `-p tcp -m tcp --dport 443` and `--dport 80` in `PVEFW-HOST-IN`.

2. Install and start nginx: `ansible-playbook -i inventories/home/ playbooks/proxmox-nginx.yml --check --diff`, read it, then run it without the flags.
   On a host without nginx, the check run shows the files it would write and says it skips the configuration test, the service and the proof, because apt installs nothing in check mode; the run without the flags does them.
   expect: `failed=0`; the last tasks pass: the front page returns `200` and an API call without a ticket returns `401`, both over 443 with the lab chain verified against the host's own CA bundle; a WebSocket upgrade request for a console path returns `401` from `pveproxy` (a `400` or `502` means the upgrade headers were not passed on); port 80 returns `301` to `https://<first name>/`.

3. Open the address from the owner's device: `https://pve.<zone>`.
   expect: the login page with no certificate warning and no port in the address. Open a VM's console (noVNC) and a node shell: both must connect. This is the part no check in the role can prove, because a console needs a login ticket.

4. After each certificate renewal (`proxmox-cert.yml`), run `proxmox-nginx.yml` again.
   why: nginx reads the certificate at a reload; the role reloads it when the certificate nginx serves is not the one on disk.
   expect: the role's reload task shows `changed` only after a renewal.

## If it fails

- nginx does not start after a reboot: `systemctl status nginx` and `journalctl -u nginx`. The drop-in makes it wait for `pve-cluster`; if `/etc/pve` is not mounted, fix that first. The web UI is still on 8006.
- The browser shows a certificate warning: the name is not in the certificate (`proxmox_cert_names`), or the device does not trust the lab root.
- The console opens and closes at once, or shows a blank pane: the upgrade headers are not reaching `pveproxy`. Check `/etc/nginx/conf.d/proxmox.conf` for `proxy_set_header Upgrade` and `Connection`, and that nothing else (a second proxy) sits in front.
- `443 times out from the browser`: the host firewall rule is not in yet (step 1).

## Exit

Remove `/etc/nginx/conf.d/proxmox.conf`, `systemctl disable --now nginx`, and take the 443 and 80 rows out of `proxmox_firewall_rules`, then run the firewall role. The web UI is on 8006 as before.
