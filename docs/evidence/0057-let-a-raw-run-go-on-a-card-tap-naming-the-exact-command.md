---
record: D-0057
batch: RB-0233 (2026-11-14), the drafting agent's reads of this repository for D-0057, between 19:10 and 19:30 UTC
researched: 2026-11-14
method: D-0034, D-0036, D-0041, D-0042 and D-0044 read at main 97ebeb2, with line numbers; the certificate roles, the proxy runbook and the workflows folder read and searched at the same commit
checks: none independent yet; the reviewer thread and the council check it with the PR
---

# Evidence for D-0057: a raw run on a tap naming the exact command

This file summarises what was read for D-0057. Nothing was run against the lab.

## Question

What does D-0041 rule 3 ask for a raw run today, what has already moved from typed words to a tap, and which raw runs wait on it?

## Findings

1. **Rule 3 today.** D-0041 line 63 says a raw run of a layer without its pipeline job needs the owner's typed words naming the exact command; line 64 says each such run is listed in the layer's runbook. Line 112 (Consequences) says raw runs go on, on the owner's typed words [1] (measured).
2. **The owner's message.** D-0042 rule 6 cites the owner's message of 2026-11-14 07:47 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNNLn48f4BruWkqptU1TmBMV), which ended typed go lines for the build-out; D-0042 rule 4 made a card tap the replacement, an agent pick (D-0042 line 129) [1] (measured).
3. **The precedent.** D-0042 rule 4 (line 115) keeps the owner's approval of a box limit change as a tap, and line 129 says the tap replaces the typed line D-0036 rule 6 asked for. D-0036 line 81 now reads that way, "since D-0042" [1] (measured).
4. **Who accepts a rule change.** D-0042 rule 11 (line 134) says a change that removes a step from rule 6 needs the owner's tap; rule 6 (lines 123 to 129) lists firewall and tailnet, deletes, secrets, access rights, money and the box's limits. D-0034 rule 4 (line 65) says that since D-0042 the reviewer's and the council's pass approves a PR that loosens the rules for now [1] (measured).
5. **The card form.** D-0034 rule 1 (line 62) says what a card names, rule 5 (line 66) pins the tap to what it names, and rule 6 (line 67) voids a disowned tap [1] (measured).
6. **The Mac's guard.** D-0044's Context (line 28) says the Mac's guard accepts only typed words [1] (measured). Its source is not in this repository; it was not tested for this record.
7. **The certificate copy.** `lab_host_cert/defaults/main.yml` lines 10 and 11 say the certificate lasts 90 days, cert-manager renews it 30 days early, and the copy must run at least every 30 days. `lab_host_cert/tasks/main.yml` lines 15 and 16 run its tasks delegated to c1's issuer host with `become: true`. No workflow in `.github/workflows/` names `proxmox-cert.yml` or `proxmox-proxy.yml` [1] (measured).
8. **The host job.** Runbook `serve-proxmox-on-443.md` line 6 says the host job is not built and that nothing applies the proxy playbook until it exists [1] (measured).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1 and 2 are the context. Finding 3 is the chosen form and rule 6. Finding 4 is how the record is accepted and rule 4. Finding 5 is rules 1 and 2. Finding 6 is rule 5 and the first Bad consequence. Findings 7 and 8 are the two raw runs waiting.

## Limits

- The Mac's guard was not read; finding 6 rests on D-0044.
- No raw run was tried on a tap.
- The host job's key line rests on the runbook and its plan, not on built code.

## References

Relied on (the decision depends on these), read 2026-11-14:

1. This repository at main 97ebeb2: `docs/decisions/0034-let-a-card-tap-naming-a-pr-and-head-count-as-the-owners-go.md`, `0036-let-the-agent-box-apply-its-own-reviewed-setup.md`, `0041-run-every-lab-and-cloud-change-through-one-logged-pipeline.md`, `0042-let-agents-approve-every-reversible-change-in-the-owners-place.md`, `0044-let-the-agent-box-apply-limit-changes-main-approves-by-digest.md`; `hosts/ansible/roles/lab_host_cert/`; `hosts/ansible/playbooks/proxmox-cert.yml`; `docs/runbooks/serve-proxmox-on-443.md`; `.github/workflows/`.
