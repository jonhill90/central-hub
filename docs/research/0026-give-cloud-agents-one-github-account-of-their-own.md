---
record: D-0026
batch: RB-0093 (2026-10-28), with RB-0018 (2026-10-16) behind it
researched: 2026-10-16 to 2026-10-28
method: GitHub and Microsoft documentation read in full or as fetched sections; read-only GitHub REST calls from the agents' environment; one call with a made-up token
checks: "RB-0093's independent check re-fetched all 15 source rows (14 hold, 1 weaker) and re-ran 5 measured rows (all reproduce); RB-0018 had a daily claim check (8 supported)"
---

# Evidence for D-0026: which GitHub identity the cloud agents use

This file summarises the research behind D-0026. It adds nothing the research did not find.

## Question

Which identity lets GitHub tell the agents from the owner, so that GitHub can require the owner's approval to merge, given the environment the cloud agents run in?

## Findings

1. **Today agents act as the owner.** A GitHub API call from an agent session returns the owner's account (measured, RB-0093).
2. **The environment replaces the caller's token.** A request with a made-up token still returned the owner's account. A valid App token was not tried (measured, with the limit inferred, RB-0093).
3. **`protect-main` asks for 0 approvals**, with no code-owner review and no last-push approval, and no bypass actors (measured, RB-0093).
4. **Agents can push workflow files.** An agent's commit added a workflow file in PR #50 (measured, RB-0093).
5. **Machine accounts.** GitHub's terms allow one free machine account per person, set up by a human, who is responsible for its actions [1] (sourced, RB-0018).
6. **Collaborators on a personal repository** always have write access; they can merge PRs and submit reviews that affect mergeability [2] (sourced, RB-0018).
7. **Rulesets** can require approvals from people with write access or from a code owner; reviewer teams are not available on user-owned repositories [3] (sourced, RB-0093).
8. **GitHub's practice:** a GitHub App for long-lived integrations, with fine-grained permissions, per-repository access and short-lived tokens [4] (sourced, RB-0093).
9. **Microsoft's practice:** non-human accounts for automated sign-in, such as managed identities, workload identities or certificates [5] (sourced, RB-0093).
10. **Blocking workflow-file pushes** with a push ruleset is possible only on private and internal repositories [6] (sourced, RB-0093 independent check).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1 and 2 rule the Foundation's per-agent Apps out for the cloud agents for now and lead to option 1. Findings 5 and 6 set rule 1 and the "Bad" consequences. Findings 3 and 7 set rule 4. Findings 4 and 10 set rule 6 and the open item 2 question. Finding 2's limit is why rule 2 tests before the switch.

## Limits

- Whether the environment carries a newly connected account was not tested; rule 2 is that test.
- Whether an owner can override a review-requiring ruleset on a personal account is untested (RB-0018 gap 3); Foundation V12 covers it.
- The price of a second machine account was not fetched.

## References

Relied on (the decision depends on these):

1. GitHub, "GitHub Terms of Service" (machine accounts). <https://docs.github.com/en/site-policy/github-terms/github-terms-of-service>, fetched 2026-10-16.
2. GitHub, "Permission levels for a personal account repository". <https://docs.github.com/en/account-and-profile/reference/permission-levels-for-a-personal-account-repository>, fetched 2026-10-16.
3. GitHub, "Available rules for rulesets". <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>, fetched 2026-10-28.
4. GitHub, "Deciding when to build a GitHub App". <https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/deciding-when-to-build-a-github-app>, fetched 2026-10-28.

Background:

- [5] Microsoft Learn, "Recommendations for enabling automation in your workload". <https://learn.microsoft.com/power-platform/well-architected/operational-excellence/enable-automation>, fetched 2026-10-28.
- [6] GitHub, "About rulesets". <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets>, fetched 2026-10-28 by the independent check.

The research batches' working files are private.
