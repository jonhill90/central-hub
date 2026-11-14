---
record: D-0044
batch: RB-0228 (2026-11-14), the drafting agent's reads and measurements for the VPS apps, between 08:23 and 09:30 UTC
researched: 2026-11-14
method: each project's licence file and README read from its repository; official docs pages opened; GitHub issue and code searches; package listings and network state measured on the VPS over Tailscale SSH; Proxmox and OpenBao source read
checks: "RB-0228 had no independent research check. Three council threads and the reviewer thread checked the design; a reviewing agent checks this file against it"
---

# Evidence for D-0044: OmniRoute, OpenClaw and Hermes Agent on the VPS

This file summarises the research behind D-0044. It adds nothing the research did not find.

## Question

Can OmniRoute, OpenClaw and Hermes Agent run on the owner's VPS as FOSS with no paid feature, without reaching the lab and without a key on a host where agent sessions are root, and how does each key get there?

## Findings

1. **Licences.** OpenClaw: MIT, "Copyright (c) 2026 OpenClaw Foundation" [1]. Hermes Agent: MIT, "Copyright (c) 2025 Nous Research" [2]. OmniRoute: MIT [3] (measured, each LICENSE file read).
2. **Paid editions.** OpenClaw's README says it "has no paid tier, hosted service, or token" [1]. Nous Portal is a paid subscription that bundles hosted tools; the agent also runs with the user's own keys [2]. No commercial or enterprise licence text in OmniRoute's code (code search, 0 hits) [3]. (sourced and measured)
3. **Memory.** OpenClaw's DigitalOcean guide runs it on 1 GB and says to move to 2 GB on out-of-memory [4]; two open issues report the gateway growing to about 3 GB and about 1 GiB over days [5]. OmniRoute's Docker guide asks at least 2 GiB for light use and at least 10 GiB for one coding agent [6]. Hermes Agent's docs give no figure; a third-party guide quotes 2-4 GB [7]. (sourced)
4. **Ports.** OpenClaw's gateway listens on 18789 on loopback by default [4]; OmniRoute on 20128 with `APP_BIND_HOST` defaulting to 127.0.0.1, and its guide warns that `0.0.0.0` with `REQUIRE_API_KEY=false` exposes an anonymous proxy [6]. (sourced)
5. **Redis and Valkey.** Redis 8 is under RSALv2, SSPLv1 or AGPLv3 [8] (measured), and Redis Software holds back Active-Active, Flex and Redis Data Integration [9] (sourced). Valkey is BSD-3-Clause [10] (measured). OmniRoute's Redis vector store names "standard Redis / Valkey instances" [3] (measured).
6. **Packages on the VPS.** AlmaLinux 10 appstream has `podman` 5.8.2, `valkey` 8.0.11, `catatonit` 0.2.1 and `nodejs24` 24.22.1; none is installed (measured, `dnf list`, 2026-11-14 08:38 and 09:18 UTC). OpenClaw needs Node `>=24.16.0 <25 || >=26.1.0` [11] (measured, `npm view`).
7. **OpenClaw's Podman sandbox.** `sandbox.backend: "podman"` uses the native CLI; rootless Podman is supported with a nonzero sandbox user; the host needs `catatonit`; "Browser sandboxing is not supported by Podman"; a containerized gateway "creates sibling sandboxes through the host's local Podman engine" [12]. (sourced)
8. **The VPS today.** sshd listens on 0.0.0.0:22, firewalld is inactive, and route acceptance is off (measured, 08:04 to 08:26 UTC).
9. **Tailnet policy.** No grant has `tag:vps` as source; `tag:agent` and `tag:github-actions` may log in to `tag:vps` as root; the box's tag has no destination and a test denies it `tag:vps:22` [13] (measured, `main` at acd2842). Nothing else in this repository names `tag:github-actions` (measured, `grep -rl`).
10. **Tailscale Serve.** Serve "requires you to enable HTTPS certificates in your tailnet" [14]; enabling them publishes machine names and the tailnet DNS name on a public ledger [15] (sourced). `CertDomains` is empty on the VPS and on an agent node (measured, 09:18 UTC), so they are off.
11. **SSH tests.** The policy file's `sshTests` take `src`, `dst`, `accept`, `check` and `deny`, and the tailnet rejects a policy whose tests fail [16]. (sourced)
12. **Repositories.** A request to let a GitHub App installation token create a repository in a personal account is open with no answer [17] (sourced). The agents' session tools may not create a repository (session rules; not tried).
13. **OpenBao's web UI.** It is on with `ui = true`, served at `/ui/` on the listener's port, and lets a user create, read, update and delete secrets [18] (sourced). This repository's OpenBao role sets `ui = true` and listens on 443 [19] (measured). D-0038 gives machine logins only (AppRole and JWT) and says the dev store holds nothing of value [20] (sourced).
14. **Anthropic's terms.** Anthropic "does not permit third-party developers ... to route requests through Free, Pro, or Max plan credentials" [21]. (sourced)

## Not checked

- Nothing was installed; every figure about the apps' behaviour on this host is from their docs and issues.
- Whether the VPS provider's own firewall blocks public port 22.
- Hermes Agent's ports (8642, 9119) come from a third-party guide only [7].

## Sources

1. <https://github.com/openclaw/openclaw>
2. <https://github.com/NousResearch/hermes-agent>
3. <https://github.com/cheaper-inference/OmniRoute>
4. <https://docs.openclaw.ai/install/digitalocean.md>
5. OpenClaw issues #195497 and #184843, <https://github.com/openclaw/openclaw/issues>
6. <https://raw.githubusercontent.com/diegosouzapw/OmniRoute/HEAD/docs/guides/DOCKER_GUIDE.md>
7. <https://fast.io/resources/hermes-agent-docker-deployment-production/>
8. <https://github.com/redis/redis/blob/unstable/LICENSE.txt>
9. <https://redis.io/compare/oss-vs-enterprise/>
10. <https://github.com/valkey-io/valkey/blob/unstable/COPYING>
11. <https://www.npmjs.com/package/openclaw>
12. <https://docs.openclaw.ai/gateway/sandboxing/podman-backend.md>
13. [`hosts/terraform/home/tailnet-policy/policy.hujson.tftpl`](../../hosts/terraform/home/tailnet-policy/policy.hujson.tftpl)
14. <https://tailscale.com/docs/features/tailscale-serve.md>
15. <https://tailscale.com/docs/how-to/set-up-https-certificates>
16. <https://tailscale.com/docs/reference/syntax/policy-file.md>
17. <https://github.com/orgs/community/discussions/116331>
18. <https://openbao.org/docs/configuration/ui/>
19. [`hosts/ansible/roles/openbao/templates/openbao.hcl.j2`](../../hosts/ansible/roles/openbao/templates/openbao.hcl.j2)
20. [D-0038](../decisions/0038-run-openbao-on-its-own-vm-as-the-secrets-store-with-sops-for-bootstrap-files.md), rules 3 to 6
21. <https://code.claude.com/docs/en/legal-and-compliance>
