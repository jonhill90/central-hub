---
record: D-0044
batch: RB-0228 (2026-11-14), the drafting agent's reads and measurements for design A1, between 08:40 and 09:30 UTC
researched: 2026-11-14
method: this repository's box-apply, its limits, the role's tasks and the sudo rules read at main; the baseline's own box-apply run against main on a local checkout; the sudoers manual and GitHub's environments documentation read; the four checks of the owner's rule of 2026-11-14 07:24 UTC for each claim that something can or can't be done
checks: none independent yet; the reviewer thread and the council check it with the PR
---

# Evidence for D-0044: the box applies a limit change that main approves by its digest

This file summarises what was read and measured for D-0044. Nothing in it was run on the agent box.

## Question

Can the agent box's baseline move past a limit change with no apply from the controller, using only what is installed on the box today? And if not, what is the smallest change that lets later limit changes do so?

## Findings

1. **What the box stops on today.** `box-apply.py` hasn't changed since 9d519572, and neither has the list of repository limit paths [measured: `git log 9d519572..main` on those files]. Its own `read_limits`, `limit_files` and `limit_keys`, run against main at 0e6e522 with those rules, find 117 changed files and 19 limit hits. Twelve are role files (`rebuild.sh`, `runner-job-started.sh`, `secrets-bundle.sh`, `secrets-store.sh`, `tailnet-stack.sh`, two task files, three templates and `sudoers.j2`) and eight are keys in `defaults/main.yml`. So it stops with exit 3 [measured]. The box's baseline was 9d519572 when it was last read there [measured on the box by the builder, 2026-11-14 07:5x UTC].
2. **Who runs as root.** The sudo rules give root only for `box-apply.py plan` and `box-apply.py apply`. Every wrapper runs as the keys user, for sessions and the runner alike [measured: `templates/sudoers.j2`]. sudo matches arguments exactly: "If a Cmnd has associated command line arguments, then the arguments in the Cmnd must match exactly those given by the user" [1].
3. **No unit runs code from main as root.** The units that start a wrapper run as the keys user. The two root units run fixed `nft` and `nmcli` commands [measured: `templates/*.service.j2`].
4. **A self-apply never writes `box-apply`.** Every task in `self_apply.yml` and `self_apply_baseline.yml` has `when: not agent_box_self_applying` [measured]. So no merged change can change `box-apply` through `box-apply`. The change that adds rules 1 and 2 needs one apply from the controller.
5. **GitHub environments.** Required reviewers can be set, and "users who initiate a deployment cannot approve the deployment job, even if they are a required reviewer" when self-review is prevented. On the Free, Pro and Team plans, required reviewers are available only for public repositories [2]. This was not tested here.
6. **The code.** `test_box_apply.sh` checks 8a to 8h pass on #308's head 39e0966, and so do checks 1 to 7 [measured].

## Checks (the owner's rule of 2026-11-14 07:24 UTC)

| Claim | Web search | Issues and code | Docs index | Hands-on |
|---|---|---|---|---|
| No installed code moves the baseline past a limit change | not applicable: this repository's own code | code read (findings 2-4) | runbook `apply-the-agent-box-from-itself.md` | the baseline's own `box-apply` run against main (finding 1) |
| sudo matches arguments exactly | the sudoers manual found by web search | not done | the sudoers manual [1] | not done on the box |
| GitHub can prevent self-review | search on required reviewers and prevent self-review | not done | GitHub's environments page [2] | not done |

## Limits

- I have no shell on the box. The baseline value comes from the builder's run of `box-apply plan` there.
- The approved limit apply has run only against a stand-in for `ansible-playbook`, never on the box.

## References

1. sudoers manual, "Cmnd_List": <https://www.linux.org/docs/man5/sudoers.html>
2. GitHub Docs, "Deployments and environments": <https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments>
