---
id: STD-0005
title: Tests for specs and hosts code
status: active
scope: how each acceptance criterion in a spec under `docs/specs/` names the test that proves it, and which lints and tests run on every PR that changes code under `hosts/`
owner-system: 8 Platform
why: written after the owner asked on 2026-10-27 at 04:22 UTC whether central-hub is missing tests and lints and said they expected test-driven development alongside spec-driven development; the owner accepted it with PR #50 on 2026-10-28, and each rule names its own origin
follows: [Kent Beck's test-driven development (Martin Fowler, "Test Driven Development", 2023), Martin Fowler "Specification By Example", HashiCorp "Testing HashiCorp Terraform" (Rosemary Wang, 2024), OpenTofu "Command test", GitHub Spec Kit "Specification-Driven Development" Article III, ansible-lint profiles]
check: "`.github/hosts-check/run.sh`, run by workflow `hosts` on every PR; rule 3 is checked by `run.sh terraform`; rules 1 and 2 by a reviewing agent"
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-28T02:22:38Z
  approved-commit: aafa317908f19ce1fd74f9c52e971b6930661463
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNVYXFo9DJzkW59rqaB2NZqG
  approval-names: "PR #50 and head aafa317, in the message itself"
  check: the thread that drafted it read the message in its project thread; it names PR jonhill90/central-hub#50 and head aafa317 itself, and the head was still aafa317, mergeable and green at 2026-10-28T02:23Z. The skip of name[casing] and var-naming[no-role-prefix] in ansible-lint was listed in the PR as agent pick 1 and is accepted with the PR. An independent check by a reviewing agent is still to do.
  merged: PR #50 merged at 2026-10-28T02:41:25Z as 58893c2
---

# STD-0005: Tests for specs and hosts code

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

An agent wrote this standard, and the owner accepted it with PR #50. Each rule names where it came from.

## Levels

Five levels, from the Terraform test pyramid (HashiCorp, "Testing HashiCorp Terraform"), with the tools this repository uses at each.

| Level | Question it answers | Tools here | Runs |
|---|---|---|---|
| 1. Lint | Is the code well formed and does it follow the rules? | `tofu fmt`, `tofu validate`, tflint; `ansible-playbook --syntax-check`, ansible-lint (production profile); shellcheck, actionlint; `check_hosts.py` for STD-0004 | every PR, in CI |
| 2. Unit | Does the plan or the rendered manifest hold the right values? | `tofu test` with `command = plan` and mocked providers; role templates rendered with made-up values and checked by kubeconform | every PR, in CI |
| 3. Contract | Are the inputs what the code expects? | variable `validation` blocks, `precondition` and `postcondition`; each role's `meta/argument_specs.yml` | every PR, through levels 1 and 2 |
| 4. Integration | Does the real lab end up as the code says? | `tofu plan` after apply shows "No changes"; a second playbook run, or `--check`, shows `changed=0` | on the lab, by the agent that applies; results go in the PR's Validation Evidence |
| 5. End to end | Can someone use what was built? | the smoke tests in roles `k8s_gateway` and `k8s_certs`; `kubectl` and `cilium status` checks in the specs | on the lab, the same way |

Levels 1 to 3 need no lab and no secret, so CI runs them. Levels 4 and 5 need the lab, which CI cannot reach before the Activation gate passes (CLAUDE.md).

## Rules

1. **Each criterion names its test.** Every acceptance criterion in a new spec MUST name the test that proves it: a test run as `<path>::<run name>`, for example `hosts/terraform/home/k8s/tests/k8s.tftest.hcl::nodes_on_prod_with_gateway_dot_one`, or the command for a level 4 or 5 check. A criterion that can be checked without the lab MUST have a level 1 to 3 test.
   Origin: an agent pick, following "acceptance scenarios become tests" (Spec Kit) and examples as tests (Fowler, "Specification By Example").
2. **Test first.** For new code, the agent writes the test for a criterion first, runs it and sees it fail, then writes the code until it passes, then tidies both (red, green, refactor). The PR's Validation Evidence shows the failing run and the passing run.
   Origin: Kent Beck's test-driven development as Fowler describes it; Spec Kit Article III makes it mandatory for its users. Applying it here is an agent pick.
3. **Every Terraform run folder has offline tests.** Each run folder MUST have at least one `tests/*.tftest.hcl` file with at least one `run` block, and `run.sh terraform` fails when one is missing.
   Origin: an agent pick; the file layout is OpenTofu's (`tofu test` reads `*.tftest.hcl` in the folder or in `tests/`).
4. **Tests need no secret and no lab.** Level 1 to 3 tests MUST use mocked providers and made-up values: `example.com` (RFC 2606), `192.0.2.0/24` (RFC 5737), or names in the STD-0001 shape that are not real machines. They MUST NOT read a secret or reach a real host.
   Origin: CLAUDE.md rule 4 (public repository) and rule 5 (no secrets in PR workflows).
5. **The test and the code have different authors where a spec has criteria.** The agent that writes the code does not edit the spec's acceptance criteria (D-0007 rule 4). A PR that makes a failing test pass by changing the test's assertion SHOULD say why in its description.
   Origin: D-0007 rule 4; the second sentence is an agent pick.
6. **No hidden skips.** A test MUST NOT be skipped or deleted to make CI pass. A lint rule is turned off only in the tool's settings file under `.github/hosts-check/`, with the reason and the count of findings it hides; a single `# noqa` names its rule and gives its reason on the same line.
   Origin: an agent pick.
7. **Pinned tools.** Every lint and test tool is pinned to a version that follows STD-0003, and its source is checked: Go tools by the Go checksum database, Python tools by hash, providers by each run folder's lock file, schemas by SHA-256.
   Origin: STD-0003; D-0019 rule 2 does the same for the docs checks.

Example that passes: the spec "Build the home lab from code and the first cluster c1" logs on 2026-10-26 that c1's nodes sit on VNet `prod`. The test run `hosts/terraform/home/k8s/tests/k8s.tftest.hcl::nodes_on_prod_with_gateway_dot_one` plans the nodes against a mocked provider and fails if a node is on another VNet or its gateway is not `prod`'s `.1` address.

## Known limits

- `tofu test` cannot import under a mocked provider (OpenTofu 1.13 stops with "Importing is not supported in testing context"), so `run.sh` tests a copy of each run folder without `imports.tf`.
- The kubeadm and encryption config templates, and manifests written inline in task files, are not rendered or checked yet.
- The custom resource schemas come from a community catalogue, not from the exact CRD versions the roles install.
- No Molecule scenarios: roles are tested on the lab (level 4), not in containers in CI.

## Not covered here

- Policy checks on plans (for example Open Policy Agent), and tests for Kubernetes manifests once `kubernetes/` exists.
- Running level 4 and 5 tests from CI, which needs a runner inside the lab and the Activation gate.
