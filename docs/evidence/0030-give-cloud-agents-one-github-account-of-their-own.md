---
record: D-0030
batch: RB-0093 and RB-0094 (2026-10-28), with RB-0018 (2026-10-16) behind them
researched: 2026-10-16 to 2026-11-08
method: GitHub and Microsoft documentation read in full or as fetched sections; read-only GitHub REST calls from the agents' environment; one call with a made-up token; re-measured 2026-11-08 by the rewriting agent
checks: "RB-0093's independent check re-fetched all 15 source rows (14 hold, 1 weaker) and re-ran 5 measured rows (all reproduce); RB-0094's independent check sampled 22 of 37 rows (PASS WITH FIXES, fixes applied); RB-0018 had a daily claim check (8 supported)"
---

# Evidence for D-0030: which GitHub identity the cloud agents use

This file summarises the research behind D-0030. It adds nothing the research did not find, except the re-measurements of 2026-11-08 (findings 15 and 16), which are labelled.

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
11. **Two channels act as the owner.** Besides the environment's proxy, the GitHub connector the agents call as tools returns the owner's account, and its traffic does not go through the proxy (measured and sourced, RB-0094 independent check, fix 7).
12. **A token set in the environment** reaches the container unchanged; whether the proxy then forwards it to GitHub is untested. Network secrets are never attached to GitHub (sourced, RB-0094).
13. **Other routes.** The Claude coding agent on GitHub installs a GitHub App and needs a paid Copilot plan; the person who asked for such a PR can't approve it [7]. An App through the Claude Code GitHub Action runs in Actions with the App's key as a secret (sourced, RB-0094).
14. **Re-ranking.** RB-0094 ranked the machine account first as the only route documented end to end for the cloud sessions, the coding agent on GitHub second, an App through Actions for scheduled jobs, and an App token in the environment last (agent pick, RB-0094 synthesis).
15. **State on 2026-11-08.** `protect-main` requires 0 approving reviews, no code-owner review and no last-push approval, with no bypass actors; a request with no token and one with a made-up token both return the owner's account (measured, 2026-11-08).
16. **Code-owner review** applies to PRs that modify content with a code owner; the page does not say how it behaves with 0 required approvals [3] (sourced, fetched again 2026-11-08).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1, 2, 12 and 14 rule the Foundation's per-agent Apps out for the cloud agents for now and lead to the agent pick, option 1. Finding 11 sets rules 2 and 5. Findings 13 and 14 add options 4 and 5. Findings 15 and 16 set rule 4's path scoping and the test in "How this fits D-0031". Findings 5 and 6 set rule 1 and the "Bad" consequences. Findings 3 and 7 set rule 4. Findings 4 and 10 set rule 6 and the open item 2 question. Finding 2's limit is why rule 2 tests before the switch.

## Limits

- Whether the environment carries a newly connected account was not tested; rule 2 is that test.
- How code-owner review behaves with 0 required approvals is not documented; rule 2's test covers it.
- Which identity the coding agent on GitHub shows on its PRs, and whether a one-person repository can approve them, are untested (RB-0094 gap 6).
- Whether an owner can override a review-requiring ruleset on a personal account is untested (RB-0018 gap 3); Foundation V12 covers it.
- The price of a second machine account was not fetched.

## References

Relied on (the decision depends on these):

1. GitHub, "GitHub Terms of Service" (machine accounts). <https://docs.github.com/en/site-policy/github-terms/github-terms-of-service>, fetched 2026-10-16.
2. GitHub, "Permission levels for a personal account repository". <https://docs.github.com/en/account-and-profile/reference/permission-levels-for-a-personal-account-repository>, fetched 2026-10-16.
3. GitHub, "Available rules for rulesets". <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>, fetched 2026-10-28 and 2026-11-08.
4. GitHub, "Deciding when to build a GitHub App". <https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/deciding-when-to-build-a-github-app>, fetched 2026-10-28.

Background:

- [5] Microsoft Learn, "Recommendations for enabling automation in your workload". <https://learn.microsoft.com/power-platform/well-architected/operational-excellence/enable-automation>, fetched 2026-10-28.
- [6] GitHub, "About rulesets". <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets>, fetched 2026-10-28 by the independent check.
- [7] GitHub, "About third-party coding agents". <https://docs.github.com/en/copilot/concepts/agents/about-third-party-coding-agents>, read by RB-0094's independent check, 2026-10-28.

The research batches' working files are private.
