---
id: D-0061
title: Count the owner's standing go of 2026-11-18 as his go for every step D-0042 rule 6 keeps, except the limits he named
status: proposed
date: 2026-11-18
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0034, D-0036, D-0042]
supersedes: []
superseded-by:
revisit-when: the owner withdraws or narrows the standing go; a step taken under it does something the owner says it should not have; or the agents get GitHub identities of their own (D-0030) and GitHub can require the owner's approval itself
---

# Count the owner's standing go of 2026-11-18 as his go for every step D-0042 rule 6 keeps, except the limits he named

## Context and Problem Statement

D-0042 rule 6 keeps some steps for the owner: firewall and tailnet applies, deletes, secrets, access rights and money. Since D-0034 rule 9, his go for one of them is his typed words naming the step and the commit, or his tap on a card option the agents did not recommend. In practice, that meant asking him to type lines such as "Accept #512 at 882d697".

On 2026-11-18 the orchestrator asked the owner to type several such lines. He answered in the project thread "Coordinate the project in my place":

- 07:40:44 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNFcHLPyEs7Kus4RCG73RKe6): "any other lines. Like i accept everyint but you lifting my creds and buy [...] and like dont wipe my mac or install virus or leak my data".
- 07:40:57 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNGkWQaRP1PcetVDtg9g7ZZZ): "dont run rm -rf ~".
- 07:41:01 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwN8YtLJBAkzt1i6tykNmWLTf): "you know normal [...]". The agents read this as the usual limits.
- 07:41:29 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwN6a639VYLJZA5t7LB8SD6tZ): he asked why he had to type "Accept #512 at" a commit id.
- 07:45:23 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwN21gcct7pZfawWtAx2DAxFu): "stop making me type so much".

The 07:40:44 UTC line names no step and no commit, so under D-0034 rule 9 it is not his go for any one step. The orchestrator still acted on it as his go for four steps. This record says how that line counts.

## Decision Drivers

- The steps are the owner's to decide, and he decided: he accepts every step except the ones he named.
- He does not want to type step names or commit ids.
- The record of which step ran at which commit must stay, so a step can be checked or reverted later.

## Considered Options

1. Count the 07:40:44 UTC line as a standing go for every rule 6 step, except the limits he named, with the agent writing each step's name and commit.
2. Keep asking for typed words naming each step and its commit.
3. Drop steps from D-0042 rule 6.

## Decision Outcome

Chosen option: 1, because it follows his words. Option 2 is what he asked the agents to stop. Option 3 goes further than he did: he set limits on the go, he did not remove the steps.

### Rules

1. **The owner's standing go.** From 2026-11-18 07:40:44 UTC, the owner's message of that time is his go for every step D-0042 rule 6 keeps for him, including the firewall and tailnet applies of D-0036 rule 8, except those in rule 2. An agent does not ask him to type a line or tap a card for such a step.
2. **What it does not cover.** These still need his own words naming the step:
   - taking, reading or using his own credentials, such as his passwords, his accounts' sign-ins, or the password stores and browsers on his devices;
   - buying anything, or starting a charge (D-0042 rule 6, money);
   - wiping or harming his Mac, or deleting his files on it; `rm -rf ~` is named;
   - installing malware on any of his devices;
   - leaking his data: sending his data, or a secret, anywhere it is not already kept.
3. **The trail.** The agent still names each step and its commit in the PR or the run's log. Where a wrapper, a ledger or an approvals line asks for a tap id or `card_id`, it holds the message id of his 07:40:44 UTC line. The orchestrator lists every step taken under this record in its next report to him (D-0042 rule 9).
4. **His no wins.** A no, stop or revert from the owner wins at once (D-0042 rule 8). Words of his that withdraw or narrow the standing go end it, or narrow it, from that message on.
5. **What stays.** The runbooks' checks stay: dry runs, and the stops when a plan or diff is not exactly what the step expects. D-0034 rule 9 still applies to any card: a tap on the recommended option is the agents' pick. D-0042 rule 7, what stays with the owner by choice, does not change.

### Consequences

- Good: rule 6 steps no longer wait for a line he has to type.
- Good: each step still has its name and commit on record, written by the agent.
- Bad: he does not see each step before it runs. Compensating controls: the checks in rule 5, the report in rule 3, and his no in rule 4.
- Bad: whether a step falls under rule 2 is the agents' reading. When it might, the agent puts it to him as one plain question, without ids.

### Confirmation

The reviewer checks that each PR or run log of a rule 6 step names the step and its commit, and that no step in rule 2's list ran without his own words.

## More Information

- **What changes elsewhere.** D-0042 rule 6 and AGENTS.md rule 1 say the same, in the same PR (D-0001: the later record keeps the reasons).
- **How this record is accepted.** It is accepted in the PR that adds it, because that PR also writes the standing go into D-0042 rule 6 and AGENTS.md rule 1 as in force. The PR's first commits hold the record as proposed. Once the reviewer clears that head, a last commit changes only this record's status, date and accepted-evidence and its index row, naming the cleared commit (D-0001 rule 5). The reviewer's clearance of the head approves a record and a change to AGENTS.md (D-0042 rule 1). D-0059 rule 1 lets a record that amends D-0042 merge on that pass. The go it records is the owner's own words, quoted above.
