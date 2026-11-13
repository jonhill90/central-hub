---
title: Test the agents' own GitHub account before the switch
status: draft
kind: manual
trigger: once, after the owner makes the agents' machine account and before the switch in D-0030 rule 5; again after the account, its connection or the Claude GitHub App changes
runner: the owner, for the account, the invitations, the connections and the approval; an agent, in one fresh cloud session, for the checks
outcome: D-0030 rule 2's five checks have run in one cloud session connected as the agent account, and their output is in the D-0030 evidence file, pass or fail
needs: the agent account, with two-factor sign-in on, invited as a collaborator on the four repositories and with the invitations accepted; the Claude GitHub App installed on those repositories; the owner's own GitHub login on a phone or browser
private-values: [agent-account-name]
files: [docs/decisions/0030-give-cloud-agents-one-github-account-of-their-own.md, docs/evidence/0030-give-cloud-agents-one-github-account-of-their-own.md]
last-tested: not yet run
superseded-by:
---

# Test the agents' own GitHub account before the switch

**Status:** draft, written 2026-11-13 from the documentation of Claude Code's cloud sessions and D-0030. Not run.

## Can one session have the agent account while the owner's other sessions keep his?

**Not inside one Claude account.** A Claude account has one GitHub connection, made once ("You connect your GitHub account to Claude once", [Projects, Set up GitHub access](https://code.claude.com/docs/en/claude-projects.md)). In Anthropic-hosted sessions the GitHub proxy swaps in "your actual GitHub token" for git and for API requests ([Cloud environments, GitHub proxy](https://code.claude.com/docs/en/cloud-environments.md)). The documentation names no GitHub identity per session or per environment. A token set in the environment doesn't help either: the proxy replaced a made-up token with the owner's (D-0030 evidence, finding 2).

So there are two ways to run the test, and the owner picks one:

| Route | What changes | Cost |
|---|---|---|
| A. A short window on the owner's own Claude account | For the length of the test, every cloud session of his acts as the agent account | No new account; minutes; other running threads lose admin rights on GitHub during the window, because the agent account is a collaborator, not an admin |
| B. A second Claude login, connected only to the agent account | Nothing on the owner's account; the test runs in that login's own session | A second Claude plan; a project belongs to one account, so the test session runs outside the owner's project |

A self-hosted environment can carry its own git credentials ([Configure git](https://code.claude.com/docs/en/self-hosted-environments-deploy.md)), but the GitHub connector would still be the owner's, so check 2 below can't pass there. It isn't a route for this test.

## Steps

1. **The owner makes the account and invites it.** Make a GitHub account for the agents with an email he can verify, turn on two-factor sign-in, and invite it as a collaborator on central-hub, inpara, agent-notebook and obsidian-graph-3d. Sign in as the account and accept the four invitations. Put its name in the private store as `agent-account-name`, and send it to the agents in the project's chat.
   why: GitHub allows one free machine account per person, made by that person, who answers for it (D-0030 rule 1). A collaborator on a personal repository has write access, which is what the agents need, and no more.
   expect: each repository's collaborators page lists the account with write access.

2. **The owner connects both channels as the agent account.** Route A: in a private browser window signed in to GitHub as the agent account, reconnect GitHub at <https://claude.ai/connect-github>, then disconnect and connect the GitHub connector in the Claude settings' connectors page in the same window. Route B: do the same while signed in to the second Claude login.
   why: the agents reach GitHub through two channels, the proxy and the connector, and both must switch (D-0030 rule 5, evidence finding 11). Doing it in a private window keeps the owner's own GitHub session out of the authorization.
   ※ the account and its invitations come from [step 1](#steps).
   expect: the connect pages name the agent account, not the owner.

3. **Start one new cloud session, and run the checks there.** A session that was already running may still carry the old connection, so start a new one. The agent runs steps 4 to 8 in that session and keeps every command's output.
   why: rule 2 asks for one session with both channels connected as the agent account.
   expect: the session clones central-hub.

4. **Check 1, the proxy.** `curl -sS https://api.github.com/user | jq -r .login`
   why: before the switch, this returned the owner even with no token or a made-up one (evidence finding 15).
   expect: the agent account's name.

5. **Check 2, the connector.** Call the GitHub connector's own identity tool (`get_me`).
   why: the connector doesn't go through the proxy, so check 1 says nothing about it (evidence finding 11).
   expect: the agent account's name.

6. **Check 3, a push.** On a new branch `test/agent-account-check`, change one line in a scratch file under `docs/evidence/`, commit and push. Then read who pushed: `gh api -X GET repos/jonhill90/central-hub/activity -f ref=refs/heads/test/agent-account-check --jq '.[0].actor.login'`.
   why: `git push` goes through the proxy's git credential, not its API one ([Cloud environments, GitHub proxy](https://code.claude.com/docs/en/cloud-environments.md)), so it is a separate check.
   ※ the connection is from [step 2](#steps).
   expect: the agent account's name.

7. **Check 4, a PR.** Open a draft PR from that branch, then `gh api repos/jonhill90/central-hub/pulls/<number> --jq .user.login`.
   why: rule 4's review rule can only tell the agents from the owner if their PRs show the agent account as author.
   expect: the agent account's name.

8. **Check 5, the owner's approval.** The owner approves that PR from his own GitHub login. The agent then runs `gh api repos/jonhill90/central-hub/pulls/<number>/reviews --jq '.[] | [.user.login, .state, .commit_id] | @tsv'` and compares the commit with the PR's head.
   why: last-push approval only counts when the approver isn't the one who pushed. Before the switch they were the same account, so this could never pass.
   ※ the PR is from [step 7](#steps).
   expect: one line with the owner, `APPROVED`, and the PR's head commit.

9. **Record and clean up.** The agent writes the five outputs, with date and route, into the D-0030 evidence file by PR, and closes the test PR without merging. The owner deletes the test branch (the proxy refuses branch deletions).
   why: D-0030's confirmation is this output in the evidence file, pass or fail.
   expect: the evidence PR is open; the test PR is closed.

10. **Pass or fail.**
    - Any check failed: the owner reconnects his own account on both channels (Route A) and the switch doesn't happen. The record is revisited (D-0030 rule 2).
    - All five passed, and the owner has already typed his accept of D-0030: the connection stays. The switch goes on: `main-review` and CODEOWNERS (rule 4), then revoking the old token (rule 5).
    - All five passed, but D-0030 isn't accepted yet: under Route A, reconnect the owner's own account until he accepts.
   why: the test proves the route; acceptance is still the owner's typed line.

## Not covered here

- Rule 4's check that code-owner review with 0 required approvals blocks only a code-owned PR. That needs `main-review` and CODEOWNERS, which come after a pass (D-0030, "How this fits D-0031").
- Gate item 2's verifier (D-0030 rule 6).

## Related

- [D-0030](../decisions/0030-give-cloud-agents-one-github-account-of-their-own.md) and its [evidence](../evidence/0030-give-cloud-agents-one-github-account-of-their-own.md).
