---
id: STD-0006
title: Use only free and open-source components, with no open core
status: active
scope: every outside component the lab runs or its code pulls in (software, container images, charts, packages, providers, collections, GitHub Actions and downloads under `hosts/` and `.github/`), and every hosted service the lab depends on
owner-system: 8 Platform
why: the owner's rule of 2026-11-14 04:43 to 04:44 UTC in the project chat (FOSS, not merely open source; nothing where a paid edition holds a feature back), on top of REQ-0032 (components are FOSS and open standards, and the system must not lock hard to one vendor); the owner kept OPNsense for now at 05:11:29 UTC the same day
follows: ["Free Software Foundation, What is Free Software?", "Open Source Initiative, The Open Source Definition", "SPDX License List"]
check: "`.github/foss-check/check_components.py`, run by workflow `foss` on every PR; rules 1 to 3 are judged by the agent that fills a register row, and checked again by a reviewing agent"
accepted-evidence:
  approved-by: owner
  approved-at: 2026-11-14T06:30:41Z
  approved-commit: 669c7fc1c7a35699066c621402e546ca6e3bed24
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNBs2MstPeufRMzK1m6UU6FK
  approval-names: "PR #277 and head 669c7fc, accepting STD-0006 with Tailscale kept per the owner's 2026-11-10 card, in the message itself"
  check: the Plan thread read the message in the orchestrator thread on 2026-11-14 at 06:31 UTC; it names PR #277 and head 669c7fc itself. A reviewing agent checks it again on this PR.
  merged: PR #277 merged at 2026-11-14T06:31:19Z as 3f795d90d139425c6b1e3c72cb9f4c29c4b22923
---

# STD-0006: Use only free and open-source components, with no open core

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

An agent wrote this standard. It is `proposed`, and not in force until the owner accepts it.

## The test

A component passes when all three hold:

1. **Its licence is free and open source.** The licence of what we run is on the OSI's approved list or the FSF's free list. A source-available licence (BUSL, SSPL, Elastic, Commons Clause and the like) fails.
2. **No feature is behind a paid tier in the edition we run.** The component fails when its owner or lead company sells an edition that holds features back from the free one. Selling support, hosting, training or tested builds of the same code is allowed.
3. **A hosted service has a stated exit path.** A service someone else runs for us (GitHub, Azure, Cloudflare) passes when its register row names what we would move to, and how. A closed service with no exit path fails.

## Rule

1. Every outside component MUST have one row in the component register, [`components.yaml`](components.yaml), with each field filled from a page or licence file opened for it, and the date it was checked.
2. A row's verdict MUST be `pass`, `hosted` or `fail`. A field that says "not checked" or "unknown" makes the row incomplete.
3. A pull request that adds an outside source MUST add or extend its row in the same pull request.
4. A component that fails the test MUST NOT be added. One already in use that fails MUST have an entry in the named exception list, [`foss-exceptions.yaml`](foss-exceptions.yaml).
5. Only the owner's go extends or changes the exception list: a message they write, or their tap on a card that names the component (D-0034). The entry names that go. An entry is either `kept` (the owner chose to keep it for now) or `pending` (it fails and waits for the owner's call).
6. A record or spec that chooses a component MUST give its licence and paid-edition check, with sources, in its evidence (REQ-0032).

## Order

Rows are kept in this order: networking first, then platform software, then hosted services. Exceptions are worked through in the same order.

## The check

`.github/foss-check/scan.py` reads every text file git tracks under `hosts/` and `.github/`, tests included, except Markdown prose. It lists every outside source they pull in:

- container images and OCI charts, by registry and path, with a Docker Hub short name such as `nginx:1.27` read as `docker.io/library/nginx`;
- downloads, package repositories and APIs, by address;
- OpenTofu providers;
- Ansible collections;
- Python packages in `hosts/`;
- GitHub Actions.

`.github/foss-check/check_components.py` fails when:

- a source matches no row;
- a source matches only what a hosted service carries for others (a GitHub release download, a Docker Hub image) and has no row for the software itself;
- a row is incomplete;
- a failing row has no exception;
- an exception names no row, or names a row that passes.

It reports `pending` and `kept` exceptions without failing. The workflow is `foss`.

Example that passes: the register row `Keycloak` matches `image:quay.io/keycloak/keycloak`. Its licence is Apache-2.0, from Keycloak's own licence file. Its paid edition is Red Hat's build, whose page names no extra features. Its verdict is `pass`.

## Not covered yet

- Packages installed from a distribution's own repositories (AlmaLinux, Debian) are not seen by the scanner. Their rows are kept by hand, as `nginx` is.
- The CI checks' own Python and Node libraries, in `.github/*/requirements*.txt` and `package-lock.json`, and the CI tools `install-tools.sh` builds from Go modules (OpenTofu, tflint, kubeconform, promtool).
- How an image is pinned, by tag or by digest. That is STD-0003's subject, not this one's.
- Runbooks under `docs/runbooks/` that install software by hand.
- Whether the check is a required status check on `main` is the owner's setting.

## Seeded from

The FOSS check of every central-hub piece, 2026-11-14 (evidence batch RB-0208), with the paid-edition pages for the rest opened on the same day. Each row carries its own sources.
