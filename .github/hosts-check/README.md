# Hosts checks

Lints and offline tests for the code under `hosts/` (STD-0005). Workflow `hosts` runs them on every PR, one job per part, with the same command you run locally.

| Path | What it is |
|---|---|
| `run.sh` | The one command: `run.sh terraform`, `run.sh ansible`, `run.sh manifests`, `run.sh scripts`, or no argument for all four. |
| `install-tools.sh` | Builds tofu, tflint and kubeconform from source at pinned versions. |
| `requirements.in`, `requirements.txt` | ansible-core, ansible-lint, ShellCheck and actionlint, pinned with hashes. |
| `check_hosts.py` | The STD-0004 rules a script can see: run folder files, no `locals`, no tracked real variable files or inventories, `meta/argument_specs.yml` in every role and no `meta/main.yml`. |
| `tests/test_check_hosts.sh` | Test cases: each breaks a copy of `hosts/` one way and expects `check_hosts.py` to fail. |
| `tflint.hcl` | tflint settings: every bundled Terraform rule. |
| `ansible-lint.yml` | ansible-lint settings: the production profile, with two style rules off and the reason. |
| `manifests/` | How the Kubernetes templates in the roles are rendered (`render.yml`, `cases.txt`, made-up `values.yml`) and the pinned schemas kubeconform checks them against (`schemas.lock`). |

The tests themselves sit next to the code: `hosts/terraform/<place>/<workload>/tests/*.tftest.hcl`.

## What each part runs

| Part | Runs |
|---|---|
| `terraform` | `check_hosts.py` and its tests; `tofu fmt -check`; then for each run folder, in a copy without `imports.tf`: `tofu init -backend=false`, `tofu validate`, tflint and `tofu test` |
| `ansible` | `ansible-playbook --syntax-check` on every playbook; ansible-lint on playbooks and roles |
| `manifests` | renders each line of `manifests/cases.txt`, then `kubeconform -strict` on the output |
| `scripts` | ShellCheck (warnings and errors) on every tracked `*.sh`; actionlint on every workflow |

## Run it locally

```sh
.github/hosts-check/install-tools.sh            # needs Go; builds into .github/hosts-check/.tools/bin
python3 -m venv .venv && .venv/bin/pip install --require-hashes -r .github/hosts-check/requirements.txt
PATH=".venv/bin:$PATH" .github/hosts-check/run.sh
```

`tofu init` downloads each run folder's providers and checks them against its lock file. On a machine that can't download them, build them and pass the folder with `TOFU_PLUGIN_DIR`; the copies then skip the lock file's hash check, so CI stays the check of record.

After you change `requirements.in`, compile `requirements.txt` with the command at its top.

## Spec criteria and their tests today

The two specs on `main` were written before STD-0005, so their criteria don't name tests yet. Their bodies are frozen once accepted (D-0007 rule 5), so the map is kept here.

| Spec criterion | Test | Level |
|---|---|---|
| Home lab and c1: nodes on VNet `prod` (decision log 2026-10-26) | `hosts/terraform/home/k8s/tests/k8s.tftest.hcl::nodes_on_prod_with_gateway_dot_one` | 2 |
| Home lab and c1: one pool per workload (decision log 2026-10-26) | `k8s.tftest.hcl::everything_in_pool_k8s`, `firewall.tftest.hcl::fresh_build_keeps_wan_down` | 2 |
| Home lab and c1: a pinned node image (decision log 2026-10-26) | `k8s.tftest.hcl::image_pinned_with_checksum` | 2 |
| Home lab and c1: one VLAN file read by both tools (decision log 2026-10-26) | `network.tftest.hcl::one_vnet_per_vlan`, `.github/docs-check/check_vlans.py` | 2 |
| Home lab and c1: `tofu plan` after apply shows "No changes" | the command, on the lab | 4 |
| Home lab and c1: `ansible-playbook --check` shows `changed=0` | the command, on the lab | 4 |
| Home lab and c1: nodes `Ready`, server version, `cilium status`, API name resolves | the commands, on the lab | 5 |
| Home lab and c1: no real hostname, domain, address, MAC or token in the diff | none yet; a reviewing agent searches the diff | |
| Web traffic: the DNS-01 token can change only the zone's records (manual 3) | `hosts/terraform/home/certificates/tests/certificates.tftest.hcl::token_limited_to_one_zone` | 2 |
| Web traffic: Gateway, routes, issuers and certificate are valid manifests | `run.sh manifests` (kubeconform) | 2 |
| Web traffic: Gateway `PROGRAMMED`, issuers and certificate `Ready`, smoke test, `openssl s_client` | the role smoke tests and commands, on the lab | 5 |
