---
title: Serve the Proxmox web UI on port 443
status: draft
kind: manual
trigger: once, after the Proxmox host's certificate is set (proxmox-cert.yml); again after each certificate renewal, at least every 30 days
runner: the host job, workflow `lab-proxmox-host` on the agent box's runner through wrapper `proxmox-host` (pick 241); it runs proxmox-proxy.yml and nothing else. Built, not installed, so until the install below nothing applies this playbook
outcome: the Proxmox web UI answers on https://pve.<zone> with the lab certificate, on port 443 with no port in the address, served by Apache httpd; port 80 redirects to it; port 8006 stays as the fallback and the agent box's lifeline
needs: the host's certificate from the lab CA (role proxmox_cert, playbook proxmox-cert.yml) with a DNS name for the host's web UI that resolves from where the owner browses; the host firewall rows for 443 and 80 (the same sources as 8006); the host job installed (below), which needs the owner's tap; python3-apt on the host for the check run
private-values: [proxmox-cert-names, agent-box-proxmox-host, agent-box-lifeline-address, agent-box-lifeline-allow]
files: [hosts/ansible/roles/proxmox_proxy/, hosts/ansible/playbooks/proxmox-proxy.yml, hosts/ansible/playbooks/proxmox-host-key.yml, hosts/ansible/roles/agent_box/files/proxmox-host.sh, hosts/ansible/roles/agent_box/tasks/proxmox_host.yml, hosts/ansible/roles/agent_box/tasks/proxmox_host_inventory.yml, .github/workflows/lab-proxmox-host.yml, hosts/ansible/roles/proxmox_firewall/defaults/main.yml, .github/hosts-check/tests/test_proxy.sh, .github/hosts-check/tests/test_proxmox_host_job.sh]
last-tested: "not yet run on the host with Apache httpd; the role was tested on 2026-11-14 against a stand-in Proxmox host in a container (Debian trixie, systemd, nginx serving as the old role left it, a stand-in pveproxy): the install with nginx still serving, the move, a failing proof, a stopped move, a killed run, an open console across a graceful reload, and a host with no nginx (.github/hosts-check/tests/test_proxy.sh); the host job was tested the same day against the same stand-in: the key line with from=, a check that changes nothing, a wrong hash refused, an apply that moves 443 (.github/hosts-check/tests/test_proxmox_host_job.sh)"
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
- The move from nginx, once per host. The role starts `proxy-cutover.sh` with `systemd-run` as its own unit, `proxmox-proxy-cutover`, so a dropped SSH connection, a killed `ansible-playbook` or a cancelled pipeline job does not stop it half-way. The script stops nginx, starts Apache httpd and runs the proofs; only then does it enable apache2 and disable nginx. A failed proof or a stop of the unit runs its rollback: apache2 stopped and masked, nginx started. A reboot part-way brings nginx back, because apache2 is enabled only at the end. The rollback retries the apache2 stop and the nginx start, and writes `rolled-back` only once nginx is running; if nginx will not start it writes `rollback-failed`. It writes `done`, `rolled-back`, `rollback-failed` or `started` to `/var/lib/proxmox-proxy/cutover.result`. A host built fresh, with no nginx, gets the same move without the nginx steps.
- Host firewall (role `proxmox_firewall`): tcp 443 and 80 from IPSet `management`, the same sources as 22 and 8006. The swap changes no port and no source.
- The test: `.github/hosts-check/tests/test_proxy.sh` (CI job `proxy`), against a stand-in host in a container, `.github/hosts-check/proxy/`.

## What the owner decides

- **The host job.** The playbook reaches the host over SSH as root, and the agent box has no SSH key for the host and reaches it on 8006 only. The host job gives the box a key, held by its own user `hostops`, used only by the root-owned wrapper `proxmox-host`, which runs this one playbook from `main`; tcp 22 opens on the lifeline for `hostops`'s sockets only; the host takes the key only from the box's lifeline address. The key is an access right and the lifeline's tcp 22 is a change to the box's packet filter, so they need the owner's tap (D-0042 rule 6); the user and the wrapper are box limits, which need no tap (D-0042 rule 4). Root on the Proxmox host reaches every guest, VM 258 included. If the host firewall refuses 22 from the lifeline address, that is a separate firewall tap (D-0036 rule 8).
- **The DNS name.** `proxmox_proxy_server_names` is the same list as `proxmox_cert_names`, set in the private inventory. The first name is where port 80 redirects.

## Install the host job

Three routes, in this order (Library plans/r1-host-job/DESIGN.md v3.1, section 6). Nothing here is applied by the pull request that adds it.

1. **On the box, through `box-apply`** (once its approved-limit mode exists, D-0044; and the owner's tap): the wrapper `proxmox-host`, its sudo lines (sessions `check` and `log`; the runner also `apply`), the hook's line for `lab-proxmox-host.yml`, user `hostops` and its folders `/etc/agent-keys-host/` and `/var/lib/agent-box-host/`. With `agent_box_proxmox_host_job: true`, the role makes the key, `/etc/agent-keys-host/id_ed25519`, as `hostops`.
   expect: `proxmox-host check` refuses with "no inventory or key", because step 2 has not run.
2. **From the controller only** (the inventory and the lifeline are skipped by every self-apply, D-0036 rule 7): `ansible-playbook -i inventories/home/ playbooks/agent-box.yml --tags proxmox_host_inventory,lifeline`, with these private values in the controller's inventory, none of them in this repository:

   | Value | Variable | Read by |
   |---|---|---|
   | The host's lifeline-side IPv4 and its public host key | `agent_box_proxmox_host: {address, hostkey}` | the job's inventory and its `known_hosts` |
   | The same address, port 22, for `hostops` only | an entry `{address, ports: [22], uid: hostops}` in `agent_box_lifeline_allow` | the lifeline filter |
   | The box's own lifeline address | `agent_box_lifeline_address` (already set) | the host's key line (`from=`) |
   | The certificate's names | `proxmox_cert_names` on the Proxmox host (already set) | the proxy role, through the job's inventory |

   expect: `/etc/agent-keys-host/inventory/hosts.yml` and `known_hosts` exist, mode 0600, owned by `hostops`; `nft list table inet lifeline` shows `tcp dport 22 meta skuid` with `hostops`'s UID; the key's public half is on the controller at `hosts/ansible/inventories/home/id_ed25519-proxmox-host.pub` (git-ignored).
3. **The host's key line, from the controller**: `ansible-playbook -i inventories/home/ playbooks/proxmox-host-key.yml`, first with `--check`, which makes the asserts and skips the write. It puts `restrict,from="<box lifeline address>" ssh-ed25519 <key> central-hub-r1` into `/etc/pve/priv/authorized_keys`, after it checks that root's `authorized_keys` is a link to that file. The file is on pmxcfs, where Ansible's file modules fail with "Operation not permitted": on the chmod of the destination ([Proxmox forum](https://forum.proxmox.com/threads/ansible-operation-not-permitted-copying-ssl-keys-directly.88310/), where a plain `cp` worked) and on a temporary file in `/etc/pve` ([Ansible forum](https://forum.ansible.com/t/help-with-blockinfile-module-running-against-proxmox/26792)). So the playbook rewrites it in place with a fixed shell script, keeping every other line. Before the write it copies the file to `/root/authorized_keys.pre-central-hub-r1`, off pmxcfs, because the file also holds the controller's key. If the write fails or the file then differs from what was meant, it writes the copy back and the run fails. The copy holds public keys only and stays on the host. Each run that changes the key file replaces it, so after a later run it holds the file as it was before that run, not the original. Removing it is a delete, so it has its own tap. The stand-in test proves the write is in place (same inode) and that a write that runs out of space is put back. A write on the real pmxcfs is not measured. This is a raw run under D-0041 rule 3, listed here until the box can reach the host by itself; its approval is the one rule 3 sets.
   expect: from the box, `proxmox-host check` prints `proxmox-host: check <hash>: ...`.

Steps 2 and 3 need the controller, whose guard takes typed words only, so today they wait (the design's section 11 blocker).

## Steps (through the host job)

The job runs only from `main`, started by hand: `lab-proxmox-host` with `action: check`, or a session on the box with `proxmox-host check`. A session can't start the workflow today (dispatch returns 403, Library plans/merge-off-mac/DESIGN.md line 33), so the apply waits on that decision. GitHub's log gets only the commit, the hash, counts and pass or fail; the full output stays in `/var/lib/agent-box-host/logs/`.

The check run needs `python3-apt` on the host: Ansible's apt module installs it itself on a real run but not in a check, and fails the check without it. Whether the host has it is not measured; if the first check fails with "python3-apt must be installed to use check mode", that is the cause.

1. Check run: `proxmox-host check`. It runs `--check --diff` and prints a hash of the commit, every diff's text and each task's changed and skipped flags.
   On a host without Apache httpd, the check run shows the files it would write and says it skips the configuration test, the move and the proof, because apt installs nothing in check mode.
   expect: the diff shows the site, the drop-in, the two scripts and `proofs.env`, and nothing under `/etc/nginx/`.

   The reviewer passes that hash (D-0041 rule 6: the host has no dev twin).

2. The run: `lab-proxmox-host` with `action: apply`, the pass's message ID and the hash. It checks again and refuses unless the hash is the same, so a new commit on `main` or a changed host stops it; then it runs the playbook, and fails the run if a task changed that the check showed neither changed nor skipped (D-0041 rule 4).
   expect: `failed=0`; the task "The move, with its proofs" is `changed`; `/var/lib/proxmox-proxy/cutover.result` starts with `done`; `ss -ltnp 'sport = :443'` names `apache2`; the last task, "The proof holds", passes.
   If the move rolls back, nginx serves again and the run fails with the unit's error. Read `journalctl -u proxmox-proxy-cutover`, fix the cause, remove `cutover.result`, and run again; a re-run does not move a host whose file says `rolled-back`, `rollback-failed` or `started`.

3. Open the address from the owner's device: `https://pve.<zone>`.
   expect: the login page with no certificate warning and no port in the address. Open a VM's console (noVNC) and a node shell: both must connect. This is the part no check in the role can prove, because a console needs a login ticket.

4. After each certificate renewal (`proxmox-cert.yml`), run `proxmox-proxy.yml` again (steps 1 and 2). `proxmox-cert.yml` is not on the host job: it reaches c1 prod's first control-plane node as root, so it still runs from the controller.
   why: Apache httpd reads the certificate at a reload; the role reloads it gracefully when the certificate it serves is not the one on disk.
   expect: the role's reload task shows `changed` only after a renewal.

5. One week after step 2, if Apache httpd has served without a rollback: purge nginx, in two pull requests.
   1. The purge. A clean-up pull request adds a task to role `proxmox_proxy` that purges `nginx` and `nginx-common` once `cutover.result` says `done`, and changes Exit below, whose way back to nginx no longer exists after the purge. That PR settles, before its apply, whether the purge needs the owner's tap under D-0042 rule 6. It is applied through the host job like step 2, under the same approvals.
      expect: `dpkg -l nginx nginx-common` reports no such packages (a purge leaves no `rc` line; `rc` means only `remove` ran); the proofs still pass.
   2. The register. After that apply, a second pull request removes nginx's row from `docs/standards/components.yaml` and its `pending` entry from `docs/standards/foss-exceptions.yaml` (STD-0006 rule 5), naming the step 5.1 run's `dpkg -l` output as the proof that nginx is gone.
      expect: the FOSS check lists no nginx.

   why: until step 5.1, nginx stays installed and disabled as the way back (see Exit), and STD-0006 still counts it as a pending fail; the register row goes only once the host shows it gone.

To install Apache httpd and leave nginx serving, set `proxmox_proxy_cutover: false`.

## Change the agents' Proxmox rights through the host job

The same wrapper runs a second job, `agent-access`, so a change to `hosts/terraform/home/bootstrap/agent-access.sh` reaches the host by a reviewed PR and no longer needs the Mac: `proxmox-host check agent-access` copies the script from the checked-out commit to the host and shows what would change (the run itself is skipped in a check), then `proxmox-host apply agent-access <pass message ID> <check hash>` copies it and runs it as root. The pass and the hash work as for the proxy job above, and the hash covers the script's exact text. It needs the host job installed first (steps 1 to 3 of "Install the host job"). The run itself changes the agents' access rights, so it needs the owner's tap on a card that names the step and the commit (D-0042 rule 6); the check does not. The script is safe to run again, prints no token secret, and its desktop switch (`DESKTOP_ACCESS`) is a committed value, so the owner's rule of no desktop rights after a build still holds.

expect: `proxmox-host: check <hash>: ...` with the job named in the line before it (`job agent-access`).

## If it fails

- Apache httpd does not start after a reboot: `systemctl status apache2` and `journalctl -u apache2`. The drop-in makes it wait for `pve-cluster`; if `/etc/pve` is not mounted, fix that first. The web UI is still on 8006.
- The browser shows a certificate warning: the name is not in the certificate (`proxmox_cert_names`), or the device does not trust the lab root.
- The console opens and closes at once, or shows a blank pane: the upgrade is not reaching `pveproxy`. Check `/etc/apache2/sites-available/proxmox.conf` for `upgrade=websocket` on the `ProxyPass` line, and that nothing else (a second proxy) sits in front.
- `443 times out from the browser`: the host firewall rows for 443 and 80 are not in.

## Exit

To take the host job's reach away: run `proxmox-host-key.yml` with `-e proxmox_host_key_state=absent` (this alone ends it), take the tcp 22 entry out of `agent_box_lifeline_allow`, and set `agent_box_proxmox_host_job: false` and remove `/etc/agent-keys-host/` (box-limit changes).

To go back to nginx on a moved host: `systemctl disable --now apache2`, `systemctl mask apache2`, `systemctl enable --now nginx` (nginx stays installed until the clean-up after the move). To serve on 8006 only: `systemctl disable --now apache2`, take the 443 and 80 rows out of `proxmox_firewall_rules`, then run the firewall role. Another proxy (Caddy, Apache-2.0) replaces only the role's insides.
