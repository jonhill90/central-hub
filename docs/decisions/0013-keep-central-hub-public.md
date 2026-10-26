---
id: D-0013
title: Keep central-hub public, and name each exception to best practice with what keeps it secure
status: proposed
date: 2026-10-26
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001]
supersedes: []
superseded-by:
revisit-when: a secret or private value is found in the repository's history; a security control the repository relies on stops being available to public repositories on the owner's plan; or the owner wants to share less of the work in public
---

# Keep central-hub public, and name each exception to best practice with what keeps it secure

## Context and Problem Statement

central-hub is a public repository, and no record says why. On 2026-10-25 at 03:07 UTC the owner said yes to keeping it public, in the project's premise review. Behind that answer: GitHub's free plan gives public repositories a full feature set, secret scanning runs on public repositories for free, and hostnames, addresses and private names already stay out of the repository (CLAUDE.md rule 4).

On 2026-10-26 at 01:35 UTC the owner gave his reasons. He wants to show the work in public: his progress, what he learns, and how the home lab grows over time. He wants the repository, the apps and the infrastructure to be secure enough that being public does not matter. He asked that wherever the work departs from a best practice, the record point out the exception and explain how it is kept secure.

This record decides whether central-hub stays public, and how it records the places where being public changes a choice.

## Decision Drivers

- **Show the work.** The progress and the learning are meant to be seen.
- **Secure whether or not it is public.** Security should not depend on the secrecy of the implementation or its components (NIST SP 800-123, §2.4, "Open Design").
- **Nothing private in it** (CLAUDE.md rule 4). A commit can't be un-published.
- **Replaceable** (REQ-0011): the choice can be undone later.

## Considered Options

1. **Keep central-hub public**, keep every secret and private value out of it, and name each exception to best practice with what keeps it secure.
2. **Make central-hub private.**

## Decision Outcome

Chosen option: **1**. The owner said yes to keeping central-hub public on 2026-10-25 at 03:07 UTC, and on 2026-10-26 at 01:35 UTC he said yes to writing it down as a decision record, with the reasons above.

Diagram: not applicable. The record sets one choice and two rules, with no components, sequence or dependency order.

### Rules

1. **Public.** central-hub is a public repository.
2. **Nothing private in it.** Secrets, encrypted secrets with weak keys, kubeconfigs, private keys, hostnames, single machine addresses, tailnet names and the owner's domain stay out of it, as CLAUDE.md rule 4 sets. Where code or a document needs one, it holds a blank that is filled in at apply time (D-0011 rule 5, STD-0001, STD-0002).
3. **Name each exception.** Where a record, standard, runbook or piece of code departs from a best practice, it says so where the choice is made, and names the compensating control: the control used in its place that gives equivalent or comparable protection (NIST SP 800-37 Rev. 2, Appendix B).

### Not decided here

- the security controls themselves, such as the secrets store and per-agent identities (Activation gate items 1 to 3);
- whether the apps and infrastructure built from this repository are reachable from the internet.

### Consequences

- Good: anyone can read the work, and the owner can point to it.
- Good: secret scanning runs on the repository for free, because it is public.
- Good: rule 3 makes each weak spot visible in the place where it is chosen, so it is reviewed rather than forgotten.
- Bad: any mistake is published at once, and a commit can't be un-published. The guards are CLAUDE.md rule 4, push protection, secret scanning and review before merge; none of them is complete.
- Bad: the layout and the tools are visible to anyone, so security can't rely on keeping them hidden. Rule 3 and the open-design driver accept this on purpose.

### Confirmation

- A reviewing agent checks each PR for private values (rule 2) and for an exception to best practice that is not named with its compensating control (rule 3).
- Secret scanning and push protection stay on in the repository settings.

## Pros and Cons of the Options

### 2. Make central-hub private

- Good: a mistake is not published to everyone at once.
- Bad: the work can't be shown, which is the owner's first reason.
- Bad: on GitHub's free plan for personal accounts, protected branches, required reviewers and code owners are listed among the paid features for private repositories.

## More Information

- **Evidence:** no research batch of its own. It rests on the owner's answers of 2026-10-25 03:07 UTC and 2026-10-26 01:35 UTC, and on these public sources, read on 2026-10-26:
  - NIST SP 800-123, "Guide to General Server Security", §2.4, "Open Design". <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-123.pdf>
  - NIST SP 800-37 Rev. 2, Appendix B, glossary entry "compensating controls". <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-37r2.pdf>
  - GitHub Docs, "About secret scanning" (free for public repositories). <https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning>
  - GitHub Docs, "GitHub's plans". <https://docs.github.com/en/get-started/learning-about-github/githubs-plans>
- **Exit path:** making the repository private is one setting. What was public stays public in any copy made before then.
- Related records: D-0001, D-0011, D-0016. Related standards: STD-0001, STD-0002.
