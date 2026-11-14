---
record: D-0041
batch: RB-0214 (2026-11-14), with the FOSS check RB-0208 of 2026-11-14 for GitHub and Forgejo
researched: 2026-11-14
method: each candidate's licence file fetched from its own repository; paid-edition and documentation pages opened for GitHub Actions, Forgejo, Semaphore UI, AWX and Atlantis; this repository's workflows, runbooks and records read
checks: none independent yet; the reviewing agent checks the sources with the PR
---

# Evidence for D-0041: one logged, tested pipeline for every lab and cloud change

This file summarises what was read for D-0041. Nothing in it was run against the lab.

## Question

Through what pipeline should every change to the home lab and to its Azure, Cloudflare and Tailscale accounts run, so each run is logged and tested and nothing runs raw? Where does it run, how does the owner's approval reach it, what is logged, which gates stand before an apply, how do the Mac wrappers retire, and does each piece pass STD-0006?

## Findings

1. **What is in place.**
   - `lab-redeploy-dev.yml` is a `workflow_dispatch` workflow on `main`. It runs on a self-hosted runner labelled `central-hub-box` and calls the box's `rebuild` wrapper, so it never sees a key [1].
   - A root-owned job-started hook on the box fails every job unless the workflow is that one, on `main`, from `workflow_dispatch` [2].
   - Its environment and runner are not registered until the agents have their own GitHub account (D-0030), because every agent acts as the owner's account and could approve as him [2].
2. **The CI runner VM.** It runs GitHub's runner as an unprivileged user, holds no lab keys, and can't reach the Proxmox API [3].
3. **The box's own logs.** `box-apply` writes one JSON line per run to its log file and keeps the last 50 runs' output [4].
4. **The Mac wrappers.**
   - They plan to a file, show the plan, and apply that file [5].
   - Each run appends a line and its output to a log on the Mac [5].
5. **Tests on every PR.** OpenTofu validate and test and ansible-lint run on each PR that changes `hosts/` [6].
6. **GitHub's run logs.**
   - They are kept 90 days by default, and a public repository can set 1 to 90 days [7].
   - Any signed-in GitHub user can view the run logs of a public repository [8].
7. **Licences and paid editions.**

   | Candidate | Licence | Paid edition |
   |---|---|---|
   | GitHub Actions runner | MIT [9] | GitHub's service is closed and hosted |
   | Forgejo, and its runner | GPL-3.0 [10] [11] | None found; its domains are held by the non-profit Codeberg e.V. [12] |
   | Woodpecker CI | Apache-2.0 [13] | None found |
   | Semaphore UI | MIT [14] | Pro and Enterprise. The free edition lacks TOTP, LDAP login, OIDC sign-in, OpenBao secrets storage and file-based log export; Pro has them [15] |
   | AWX | Apache-2.0 [16] | Red Hat sells Ansible Automation Platform as the supported product beside the upstream projects [17]; the feature split was not read |
   | Atlantis | Apache-2.0 [18] | None found; an LF Projects series [19] |

8. **Forgejo Actions and GitHub Actions.** Forgejo Actions "is designed to be familiar to users of GitHub Actions, but it is not designed to be" compatible with them [20].

## How the decision used it

- **The pick.** Findings 1 to 5 are why option 1 builds on what is in place: the workflow pattern, the hook, the wrappers and their logs.
- **Rule 7.** Finding 6 is why GitHub's log holds only a summary and the full log stays on the box.
- **Rule 8.** Finding 2 is why the CI runner VM takes only PR tests.
- **The exit path.** Findings 7 and 8 are why Forgejo is the exit, and why its workflows need rewriting.
- **Option 3.**
  - Semaphore UI fails STD-0006 rule 2 (finding 7).
  - Atlantis's apply from pull-request comments breaks CLAUDE.md rule 5 [19].
  - AWX runs on Kubernetes.

## Limits

- Nothing was run.
- AWX against Ansible Automation Platform, and Argo Workflows, were not compared feature by feature.
- Jenkins, Concourse, Tekton, GitLab CE and Rundeck were not opened.
- GitHub Actions minutes for this repository's PR tests were not measured.

## References

1. `.github/workflows/lab-redeploy-dev.yml`
2. [Run the dev lab redeploy from GitHub Actions on the agent box](../runbooks/set-up-the-lab-redeploy-workflow.md), "Not registered until D-0030 is met" and "What the workflow does"
3. [Set up the notebook's self-hosted CI runner](../runbooks/set-up-the-ci-runner.md), outcome
4. [Apply the agent box from itself](../runbooks/apply-the-agent-box-from-itself.md), "The wrapper"
5. [Allow a command for agents](../runbooks/allow-a-command-for-agents.md), the wrapper rules and "The wrappers on the owner's Mac today"
6. `.github/hosts-check/run.sh` and `.github/workflows/hosts.yml`
7. GitHub Docs, retention of Actions artifacts and logs: <https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization>
8. GitHub Docs, using workflow run logs: <https://docs.github.com/en/actions/how-tos/monitor-workflows/use-workflow-run-logs>
9. GitHub Actions runner licence: <https://raw.githubusercontent.com/actions/runner/main/LICENSE>
10. Forgejo licence: <https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/LICENSE>
11. Forgejo runner licence: <https://code.forgejo.org/forgejo/runner/raw/branch/main/LICENSE>
12. Forgejo FAQ: <https://forgejo.org/faq/>
13. Woodpecker licence: <https://raw.githubusercontent.com/woodpecker-ci/woodpecker/main/LICENSE>
14. Semaphore UI licence: <https://raw.githubusercontent.com/semaphoreui/semaphore/develop/LICENSE>
15. Semaphore UI pricing: <https://semaphoreui.com/pricing>
16. AWX licence: <https://raw.githubusercontent.com/ansible/awx/devel/LICENSE.md>
17. Red Hat, AWX and Ansible Automation Platform: <https://www.redhat.com/en/technologies/management/ansible/compare-awx-vs-ansible-automation-platform>
18. Atlantis licence: <https://raw.githubusercontent.com/runatlantis/atlantis/main/LICENSE>
19. Atlantis documentation: <https://www.runatlantis.io/docs/>
20. Forgejo Actions overview: <https://forgejo.org/docs/latest/user/actions/overview/>
