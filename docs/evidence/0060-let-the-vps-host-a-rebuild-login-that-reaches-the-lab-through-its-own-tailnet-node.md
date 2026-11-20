---
record: D-0060
batch: RB-0234 (2026-11-18), one session's reads and measurements between 06:11 and 06:21 UTC
researched: 2026-11-18
method: central-hub main read at 279c726; the VPS reached over Tailscale SSH and checked; no vendor page opened this session
checks: "No independent research check; the reviewer thread checks the record against this file"
---

# Evidence for D-0060: a rebuild login on the VPS

## Question

Can the VPS be a rebuild jump box for the lab without giving the internet-facing apps a route into the lab?

## Findings

1. **The owner's ask.** The VPS is a second jump box if Proxmox goes down (cmsg_01X43rfNYp4H1dL1V2dkfkwNXDyf8bn8y8AKU2K7JFBKhu, 2026-11-18 06:04:55 UTC) [1] (read).
2. **The VPS today.** AlmaLinux 10.2, 4 vCPU, 15 GiB; port 22 and the tailnet's own ports listen; the host layer of D-0046 is applied, so users `omniroute`, `openclaw` and `hermes` have working rootless Podman [2] (measured over Tailscale SSH, 06:12 to 06:15 UTC).
3. **The only lab route.** The lab's tailnet connector is CT 900, made by `hosts/terraform/home/remote-access` as a container on the Proxmox host [3] (read). When the host is down it is down.
4. **The policy.** No grant has `tag:vps` as source; `tag:agent` already reaches the Proxmox host's port 22 through the connector; the box's tag has no destination of its own [4] (read, `policy.hujson.tftpl` on main 279c726). Tailnet grants and SSH rules name device tags, which is why a second login with its own tag needs a second node.
5. **Local proxy ports.** A userspace `tailscaled`'s SOCKS5 or HTTP proxy listens on TCP, which any local user can open (reviewer's point, not tested here); the record uses `tailscale --socket ... nc` instead.
6. **SSH rules today.** `tag:github-actions` and `tag:agent` hold `autogroup:nonroot` on `tag:vps`, which would include the new user [4] (read, line 84 to 86 at 211fcfc).
7. **Not measured.** That a second `tailscaled` in userspace mode runs on this VPS, that the lab has an always-on device outside Proxmox, and that such a device can sit on the host's management network. Rule 7(f) of the record is the test.

## Sources

1. The owner's message above.
2. `docs/runbooks/set-up-the-vps-app-host.md`; the run log is in agent-notebook PR 499 (worklog 2026111806180001, not on main when this was written).
3. `docs/runbooks/set-up-tailnet-client-in-ct-900.md`.
4. `hosts/terraform/home/tailnet-policy/policy.hujson.tftpl`.
