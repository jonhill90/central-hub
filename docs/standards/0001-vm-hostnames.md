---
id: STD-0001
title: VM hostnames
status: active
scope: the OS hostname of every VM and physical host, local or cloud
owner-system: 8 Platform
why: Jon said yes to the proposed two-letter OS codes on 2026-10-21 at 01:12 UTC, and to the proposed option E (one hostname, no dashes) on 2026-10-21 at 01:13 UTC, in the project's VM naming work
follows: [NetBIOS computer name limit (15 characters, not all digits), RFC 1123 host name label, Kubernetes node name rules]
check: none yet in this repo; a reviewing agent checks new names by hand
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-22T07:07:51Z
  approved-commit: 1c8bfdd412eade4c2470fa7959ecbd6390b25093
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNLe3Dm7Jei52vHtd4YLEnZy
  approval-names: "PR #16 and head 1c8bfdd, in the message itself"
  check: the drafting agent read the message in the Standards system thread at 2026-10-22T07:07Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #16, which carries this evidence commit on top of the approved commit
---

# STD-0001: VM hostnames

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

## Rule

A hostname MUST be five fields joined with no separator:

`<env><os><role><what><nn>`

| Field | Length | Codes |
|---|---|---|
| env | 1 | `d` dev, `q` QA, `s` stage, `p` prod, `n` sandbox |
| os | 2 | `al` AlmaLinux, `rh` RHEL, `rk` Rocky, `ub` Ubuntu, `su` SUSE, `ar` Arch, `de` Debian, `ta` Talos, `ws` Windows Server, `wc` Windows client |
| role | 2 | `ap` app, `db` database, `fs` file server, `dc` domain controller, `cp` Kubernetes control plane, `wk` Kubernetes worker, `hv` hypervisor, `dt` desktop |
| what | 3-5 | a short word for what the machine is for |
| nn | 2 | `01` to `99` |

1. A hostname MUST be 15 characters or fewer.
2. A hostname MUST use only lowercase `a-z` and `0-9`, and MUST start with a letter.
3. A hostname MUST NOT contain dashes, dots or underscores.
4. A hostname MUST NOT include the provider, the region or the site. Those belong in the platform's resource name or tags.
5. A hostname SHOULD change only when the machine is rebuilt.
6. A new code for env, os or role MUST be added to this table, with Jon's approval, before it is used.

Server and desktop are told apart by the OS code on Windows (`ws` or `wc`), and by the role on Linux (`dt` means a desktop).

## Example that passes

`pubapdemo01`: prod, Ubuntu, app, "demo", number 01. It is 11 characters long. The example is made up and is not a real machine.

## Not covered here

- The platform's own resource name around the hostname (for example an Azure VM resource name), and the tags. The org code and the subscription words are not settled yet.
- Real machine names. This repository is public, so the names in use live outside it.
