# Hosts checks

Lints and offline tests for the code under `hosts/` (STD-0005). Workflow `hosts` runs them on every PR, one job per part, with the same command you run locally.

| Path | What it is |
|---|---|
| `run.sh` | The one command: `run.sh terraform`, `run.sh ansible`, `run.sh manifests`, `run.sh identity`, `run.sh scripts`, `run.sh backup`, `run.sh proxy`, or no argument for all seven. |
| `install-tools.sh` | Builds tofu, tflint, kubeconform and helm from source at pinned versions. |
| `requirements.in`, `requirements.txt` | ansible-core, ansible-lint, ShellCheck and actionlint, pinned with hashes. |
| `check_hosts.py` | The STD-0004 rules a script can see: run folder files, no `locals`, no tracked real variable files or inventories, `meta/argument_specs.yml` in every role and no `meta/main.yml`. |
| `tests/test_backup.sh` | The c1 backup and restore-test scripts (role `k8s_backup`) end to end: etcd 3.7.0 with test keys, a local restic repository, a volume folder; plus a missing key and a damaged pack file, which must fail. |
| `tests/test_proxy.sh`, `proxy/` | Role `proxmox_proxy` against a stand-in Proxmox host in a container (`proxy/Dockerfile`, a stand-in `pveproxy` in `standin_pveproxy.py`, nginx as the old role left it in `nginx-today.conf`). |
| `tests/test_check_hosts.sh` | Test cases: each breaks a copy of `hosts/` one way and expects `check_hosts.py` to fail. |
| `tflint.hcl` | tflint settings: every bundled Terraform rule. |
| `ansible-lint.yml` | ansible-lint settings: the production profile, with two style rules off and the reason. |
| `identity/` | The realm test: `test_realm.sh` imports the rendered realm `lab` into Keycloak 26.8.1 in a container (pinned by digest), `realm_to_json.py` turns the KeycloakRealmImport into the JSON Keycloak reads and fails on a placeholder that is used but not declared or the other way round, `check_realm.py` checks every client, every user's password and the claims in each app's ID token, and `check_theme.py` checks that the sign-in page loads the test theme in `theme/lab` (mounted the way the role mounts `k8s_identity_theme_dir`). |
| `manifests/` | How the Kubernetes templates in the roles are rendered (`render.yml`, `cases.txt`, made-up `values.yml`) and the pinned schemas kubeconform checks them against (`schemas.lock`). `parity.txt` and `values-dump.yml` feed the parity check. |
| `parity.py` | The parity check: for each line of `manifests/parity.txt`, renders what an Ansible role applies today and what Argo CD will apply from `hosts/kubernetes/<place>/<cluster>/`, and fails on any difference. |
| `project_check.py` | The project check: renders every app in each root chart's values as Argo CD does, and fails when the cluster's AppProject (`root/templates/project.yaml`) does not allow an object's namespace, a cluster-scoped kind or a chart repository. |

The tests themselves sit next to the code: `hosts/terraform/<place>/<workload>/tests/*.tftest.hcl`.

## What each part runs

| Part | Runs |
|---|---|
| `terraform` | `check_hosts.py` and its tests; `tofu fmt -check`; then for each run folder, in a copy without `imports.tf`: `tofu init -backend=false`, `tofu validate`, tflint and `tofu test` |
| `ansible` | `ansible-playbook --syntax-check` on every playbook; ansible-lint on playbooks and roles |
| `manifests` | renders each line of `manifests/cases.txt`, each `hosts/kubernetes/*/*/root` chart and each local chart under `hosts/kubernetes/*/*/apps/` (`helm lint`, `helm template`); runs `parity.py` and `project_check.py` (downloads the upstream charts named in the root values, with retries; `PARITY_CHART_CACHE=<dir>` keeps them, and CI caches that folder); then `kubeconform -strict` on the output |
| `identity` | renders realm `lab` with an extra user, imports it into Keycloak in a container, checks clients, passwords and the `groups` and `roles` claims and the sign-in theme, then runs the role's `files/delete-realm.sh` and imports it again (STD-0005 level 3) |
| `scripts` | ShellCheck (warnings and errors) on every tracked `*.sh`; actionlint on every workflow |
| `backup` | `tests/test_backup.sh`: downloads restic and etcd from their releases, each checked against a SHA-256 (the role's own versions), and runs the role's scripts |
| `proxy` | `tests/test_proxy.sh`: builds the stand-in Proxmox host in `proxy/` (Debian trixie pinned by digest, systemd as PID 1, nginx serving as role `proxmox_nginx` left it, a stand-in `pveproxy`) and runs role `proxmox_proxy` against a fresh container per case: the install beside nginx, the move, a failing proof, a stopped move, a killed run, an open WebSocket across a graceful reload, a host with no nginx. Needs a Docker that can run a privileged container |

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
