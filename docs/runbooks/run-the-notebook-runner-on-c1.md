---
title: Run the notebook's CI runner as a pod on c1
status: draft
kind: automated
trigger: once, to move the notebook's CI off VM 300; again after c1 is rebuilt, or when the runner's registration is lost
runner: an agent session on the agent box
outcome: one pod in namespace notebook-runner on c1 takes the notebook's jobs (label notebook), holds no lab key and no Kubernetes credential, reaches no lab address, and keeps running while a dev rebuild stops VM 300
needs: this runbook's code installed on the agent box (a box-limit line); the box's prod node key on prod's nodes (set-up-the-secrets-store.md step 1); a firewall pass from the agent box to prod's store on 443, which step 3 uses and which does not exist yet (the rules are central-hub #491, unapplied, and applying them is the owner's firewall step, so `ci-runner c1-token` cannot run until then); prod's store with its admin hand-over done; the GitHub App with Administration (write) on agent-notebook
private-values: []
files: [hosts/kubernetes/home/c1/apps/notebook-runner/, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_gitops/templates/source-argocd.yaml.j2, hosts/ansible/roles/agent_box/files/ci-runner.sh, hosts/ansible/roles/agent_box/files/openbao-prod.sh, hosts/ansible/roles/agent_box/files/rebuild-prod.sh]
last-tested: not yet run
superseded-by:
---

# Run the notebook's CI runner as a pod on c1

**Status:** draft, not yet run. Written on 2026-11-18.

## Why

A dev rebuild needs more memory than the host has free while VM 300, the notebook's runner ([Set up the notebook's self-hosted CI runner](set-up-the-ci-runner.md)), is running. So the preflight stops VM 300 for the whole run, and every notebook pull request waits. Measured on 2026-11-18 in dev run `rebuild-20261118T071239Z` (`rebuild log`):

| Reading | MiB |
|---|---|
| Node free memory, VM 300 running | 10297 |
| Node free memory, after the preflight stopped VM 300 | 12210 |
| What VM 300 held on the host (the difference) | 1913 |
| What dev needs: control plane 4096, worker 6144, margin 1024 (the sizes then; since 2026-11-18 3584 and 6400, 11008 with the margin; since 2026-11-19 a 512 MiB margin, 10496, then the control plane back at 4096, 11008, then the worker at 8192, 12800) | 11264 |

With VM 300 running, dev is 967 MiB short. Shrinking VM 300 to 1024 MiB frees about 900 MiB, which still leaves dev short. Dev's VMs keep their memory until the teardown, so no stage frees memory for an earlier restart either. The runner VM stopped at 07:12:55 UTC and started again at 07:43:44 UTC, after the run's own teardown.

A pod on c1 uses c1's worker, which a dev rebuild does not touch.

## Does it fit on c1's worker

The pod runs on c1's worker: the control plane carries the `node-role.kubernetes.io/control-plane:NoSchedule` taint. Measured on 2026-11-18 at 08:33 UTC with `c1-read top nodes` and `c1-read describe node` on the worker:

| Reading | MiB |
|---|---|
| Worker allocatable memory (8023144Ki) | 7835 |
| Requests of the pods on it (45%) | 3590 |
| Limits of the pods on it (129%, overcommitted) | 10178 |
| Working set now (`top nodes`, 71%) | 5586 |
| The pod's request | 512 |
| The pod's limit | 2048 |

- **Scheduling:** requests become 3590 + 512 = 4102 of 7835 (52%), so the scheduler places it.
- **Use:** at rest the working set has 7835 - 5586 = 2249 MiB of room. A job that reaches the pod's whole 2048 MiB limit leaves about 200 MiB. The kubelet starts evicting at 100 MiB available by default, so a job at its limit while the other pods peak can push the worker into eviction. The kubelet evicts first the pod whose use is furthest above its request, which would be this one. Its running job then fails and has to be re-run; GitHub does not move it to another runner by itself.
- **The host's figure is not this figure.** Proxmox counted the worker VM at 8233 of 8192 MiB on 2026-11-18 at 01:45 UTC: that is the VM's memory as the host sees it, guest page cache included, not what the pods use.
- c1 has no ResourceQuota or LimitRange in any namespace (`c1-read get resourcequota -A` and `get limitrange -A`: `No resources found`), and namespace `notebook-runner` does not exist yet.
- How much memory a notebook job really takes is not measured yet; step 6 measures it. If the worker's working set passes 7300 MiB during those runs, lower the pod's limit to 1536 MiB, or move the jobs back to VM 300, before VM 300 is retired.

## What runs

| Piece | Where |
|---|---|
| App | `hosts/kubernetes/home/c1/apps/notebook-runner`, made by the root chart only when `notebookRunner` is true |
| Switch | `k8s_gitops_source_notebook_runner`, set only by the prod wrappers `openbao-prod.sh` and `rebuild-prod.sh`. A dev cluster never sets it, so it never registers a second runner under the same name |
| Image | `python:3.12.15-bookworm`, pinned by digest: bash, git, python3 and the runner's libraries. It has no ICU, so .NET runs in globalization-invariant mode |
| Runner | the same actions/runner pin as VM 300 (`ci_runner_version`, `ci_runner_sha256`). `start.sh` downloads that release, checks its SHA-256, unpacks it into `/runner/app` on the pod's volume, registers once with `--disableupdate`, then runs |
| Registration | a one-hour token in prod's store at kv `c1/notebook-runner`, key `registration-token`, which ExternalSecret `notebook-runner-token` mounts. It is read only when the volume holds no registration |
| Updates | the box's weekly `ci-runner bump` moves VM 300's pin and the pod's pin in the same pull request |

The pod is kept apart from the cluster because it runs the code in each notebook pull request:

- No ServiceAccount token is mounted, so a job can't call the Kubernetes API.
- The namespace enforces the restricted pod security standard.
- The container runs as uid 1001 with every capability dropped and a read-only root filesystem.
- A NetworkPolicy lets nothing in. Out, it allows DNS to kube-dns and public addresses only; 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 and 100.64.0.0/10 are excepted.

## Steps

1. Check the fit again, since it changes as apps are added: `c1-read top nodes` and `c1-read describe node <worker>`.
   expect: the worker's requests plus 512 MiB stay under its allocatable, and its working set plus 2048 MiB stays under its allocatable. If not, stop here and say what would have to move.

2. Install this runbook's box code: the box-limit line that holds `ci-runner.sh` (action `c1-token`), the sudoers line and the two prod wrappers ([Set up the agent box](set-up-the-agent-box.md)).
   expect: `sudo -n -l` on the box lists `ci-runner.sh c1-token`.

3. Put a registration token in prod's store, from a session on the box: `ci-runner c1-token`.
   expect: `ci-runner: a one-hour registration token is in prod's store at kv c1/notebook-runner (registration-token)`.

4. Turn the app on: `openbao-prod gitops`. It renders the root Application with `notebookRunner` true.
   expect: `failed=0`; `c1-read get applications -n argocd notebook-runner` shows `Synced` and `Healthy` within about ten minutes.

5. Check the pod registered: `c1-read logs -n notebook-runner deploy/notebook-runner`.
   expect: `Listening for Jobs`, and on the notebook's Settings, under Actions and Runners, runner `notebook-c1` is Idle with label `notebook`.

   Run steps 3 to 5 within the hour the token lasts. A pod made before any token exists (any `openbao-prod gitops` or `rebuild-prod` run after step 2 turns the app on) does not exit: `start.sh` prints "not registered and no registration token yet" and waits for `/token/value`, so it does not restart or page `C1PodCrashLooping`. It registers once the ExternalSecret writes the token (that the kubelet fills an optional Secret volume after the pod started is expected, not yet run). If the pod picks up a token after it expired, config.sh is refused and the pod exits and restarts. Run step 3 again: the ExternalSecret reads the new token within an hour (`refreshInterval: 1h`), and the pod registers at its next restart.

6. Watch three notebook pull requests: each of their `org-check` jobs runs on `notebook-c1` and passes (the job log's first lines name the runner).
   expect: three green runs on `notebook-c1`. While each runs, read `c1-read top pod -n notebook-runner` and `c1-read top nodes` and write the pod's peak memory and the worker's peak working set into the pull request that retires VM 300. Until then VM 300 stays as the fallback, and GitHub gives each job to whichever runner is idle.

7. Retire VM 300 in its own pull request, following [the exit](set-up-the-ci-runner.md#exit) of its runbook, once step 6 passed.

## The fallback

VM 300 keeps its registration and its label until step 7, so both runners take the notebook's jobs and GitHub gives each to whichever is idle. If the pod is down, evicted or turned off, new jobs go to VM 300 with no change anywhere; a job that was running on the pod fails and is re-run. A dev rebuild still stops VM 300 meanwhile, and the pod then takes every job. Retire VM 300 only after step 6, in its own pull request.

## If it fails

- The pod's log says "not registered and no registration token in the store": step 3 did not run, or the ExternalSecret is not Ready (`c1-read get externalsecret -n notebook-runner`).
- `sha256sum` reports FAILED: the download does not match the pin. Nothing is unpacked; check the pin against the release notes.
- A job fails for a missing tool: the image lacks it. Pick an image that has it, pinned by digest, in a pull request.
- Jobs stay queued and `notebook-c1` shows as offline: the pin is more than 30 days behind a release. Merge the open bump pull request.

## Exit

Set `notebookRunner` back by leaving the switch out of the prod wrappers, run `openbao-prod gitops`, remove runner `notebook-c1` on the repository's runner page, and delete kv `c1/notebook-runner`. The app has `prune: false`, so delete namespace `notebook-runner` by hand; that is a delete and needs the owner's go.
