---
id: D-0057
title: Let a raw run of a layer that has no pipeline job yet go on the owner's tap on a card naming the exact command, in place of typed words
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0041, D-0042]
supersedes: []
superseded-by:
revisit-when: the greenfield build-out ends; the Mac's guard still refuses a tap once this record is accepted, so no raw run can go on one; a raw run goes on a tap that did not name its exact command or commit; a tap is disowned after a raw run went on it; the agents get a GitHub account of their own (D-0030); or a cluster other than c1 reads the repository
---

# Let a raw run of a layer that has no pipeline job yet go on the owner's tap on a card naming the exact command, in place of typed words

## Context and Problem Statement

D-0041 rule 3 forbids raw runs: changes made from the owner's Mac, a session's shell or a console. It allows one way round, in D-0041 line 63: "Until a layer or stack has its pipeline job, a raw run of it needs the owner's typed words naming the exact command." Line 64 lists each such run in the layer's runbook until its job exists. D-0041's Consequences repeat it: raw runs go on, on the owner's typed words (line 112).

The owner's message of 2026-11-14 07:47 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNNLn48f4BruWkqptU1TmBMV, cited in D-0042 rule 6) ended typed go lines for the build-out. D-0042 rule 4 made a card tap the replacement for the box's limits (an agent pick): it kept the owner's approval of a limit change, as a tap on a decision card in place of the typed line D-0036 rule 6 asked for (D-0042 lines 115 and 129). Rule 3 of D-0041 was not changed then, so every raw run still waits on typed words.

Two raw runs wait on this now:

- **The certificate copy to the Proxmox host.** `proxmox-cert.yml` copies c1's renewed certificate onto the host. The certificate lasts 90 days and cert-manager renews it 30 days early, so the copy must run at least every 30 days (`hosts/ansible/roles/lab_host_cert/defaults/main.yml` lines 10 to 13). Its tasks run as root on c1's issuer host (`lab_host_cert/tasks/main.yml` lines 15 and 16). It has no pipeline job.
- **The host job's first step.** The host job that would run the proxy move of D-0055 is not built (runbook `serve-proxmox-on-443.md` line 6). As planned, the box reaches the host only after one key line is put on the host, and that line can go in only as a raw run from the controller, because the box has no way onto the host before it.

## Decision Drivers

- **The owner's messages for the greenfield build-out.** His message of 2026-11-14 07:47 UTC ended typed go lines, and his messages of 07:42 to 07:44 UTC said PRs should no longer come to him for approval. The card tap and the agents' pass that replace them are agent picks (D-0042).
- **The owner keeps his approval of every raw run.** This record changes how he says yes, not whether he is asked (D-0034, "What decides stays with the owner").
- **Exactness.** A typed line is trusted because it names one command. A card can name the same command and the commit it runs from (D-0034 rules 1 and 5).
- **The same step D-0042 already took for the box's limits** (D-0042 rule 4), so one form of approval covers both.
- **Replaceable** (REQ-0011): undone by putting rule 3's typed words back.

## Considered Options

1. **A tap on a card naming the exact command and its commit**, at the step, for each raw run.
2. **Keep typed words** (D-0041 rule 3 as it stands).
3. **The agents' pass alone**, with no owner step, as for a production apply under D-0042.
4. **Build each layer's pipeline job first**, and allow no raw run until then.

## Decision Outcome

Chosen option: **1**. It keeps one owner step per raw run, names the run exactly, and is the form D-0042 already uses for the box's limits. Option 2 leaves every raw run waiting on a typed go line, which the owner ended for the build-out. Option 3 removes an owner step, which this record does not do. Option 4 leaves the certificate copy without a route until its job exists.

### Rules

1. **The tap.** Until a layer or stack has its pipeline job, a raw run of it needs the owner's tap on a decision card that names the exact command and the commit it runs from, at the step itself (the form of D-0034 rule 1). A line the owner types naming the exact command still counts.
2. **One tap, one run.** The tap covers that command at that commit only. If either changes, a new card goes out (D-0034 rule 5). A disowned tap is void (D-0034 rule 6).
3. **Listed as now.** Each raw run is still listed in its layer's runbook with its date, now also with the card's message id, and stays listed until the layer's job exists (D-0041 rule 3).
4. **D-0042 rule 6 is unchanged.** A raw run that is also a rule 6 step (a firewall or tailnet apply, a delete, a secret, an access right, money or a box limit) already needs the owner's tap; this record adds nothing to it. A raw run that is none of those still gets its own tap under rule 1, so no owner step is removed.
5. **The Mac's guard is not changed by this record.** The guard on the controller accepts only typed words (D-0044 Context). Until the guard itself takes a tap, which is the owner's own script and a separate change, a raw run from the Mac still goes only on typed words. This record changes the rule, so that a guard change is all that is left.
6. **What this changes, on acceptance.** D-0041 rule 3's second line and its Consequences line 112 are edited to read as the current rule, with a "since D-0057" note, as D-0036 rule 6 was for D-0042.

### Consequences

- Good: the owner approves raw runs the way he approves everything else he keeps, by a tap, with no typed line.
- Good: no owner step is removed. Each raw run keeps its own approval, named exactly.
- Bad: on its own this record moves nothing, because the Mac's guard still takes only typed words (rule 5). Compensating control: it is stated here, so the guard change is the one step left, and it is the owner's.
- Bad: a tap is one click and a typed line is not, so a tap is easier to give without reading. Compensating control: the card names the exact command and commit, and the owner's no wins at once (D-0042 rule 8).
- Neutral: the aim is still no raw runs. Each layer's pipeline job retires its raw runs as before (D-0041 rule 3).

### Confirmation

- After acceptance, D-0041 rule 3 and its line 112 say a tap naming the exact command, and a runbook that lists a raw run gives the card's message id.
- The first raw run under this record, once the guard takes a tap, names its card in the layer's runbook, and the orchestrator lists it in its next report to the owner (D-0042 rule 9).

## Pros and Cons of the Options

### 2. Keep typed words

- Good: nothing changes.
- Bad: no raw run goes until a typed line comes, so the certificate copy has no route.

### 3. The agents' pass alone

- Good: no owner step at all.
- Bad: a raw run skips the pipeline's logs and tests (D-0041), so it keeps an owner step; the owner did not ask to drop it [pick].

### 4. Pipeline jobs first

- Good: it reaches the end state, no raw runs, directly.
- Bad: the certificate copy runs as root on c1 production, so its job needs a design of its own, and the copy is due at least every 30 days.

## More Information

- **Evidence:** [0057](../evidence/0057-let-a-raw-run-go-on-a-card-tap-naming-the-exact-command.md).
- **How this record is accepted:** by the reviewer's clearance and the three council passes of the same head (D-0042 rule 1). It removes no step from D-0042 rule 6, so D-0042 rule 11 (line 134) does not send it to the owner, and since D-0042 a rule change is approved by that pass (D-0034 rule 4, line 65). That reading is the agents', and the owner can change it.
- **Exit path:** a PR putting rule 3's typed words back.
- Related records: D-0001, D-0034, D-0036, D-0041, D-0042, D-0044.
