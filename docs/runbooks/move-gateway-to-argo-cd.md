---
title: Move c1's Gateway and app routes from Ansible to Argo CD
status: draft
kind: automated
trigger: on request (step 9 of spec 2026-11-c1-apps-under-argo-cd)
runner: an agent lane, through the owner's Mac (D-0022)
outcome: Argo CD's Application `gateway` is Synced and Healthy, Gateway `apps` keeps its address and its listeners (`http`, `https`, and `http-short`, `https-short` while `shortNames` is on), Grafana still opens over HTTPS, and Ansible no longer applies the Gateway or Grafana's route
needs: the lab clone of central-hub with its private inventory; SSH to c1's control plane as D-0022 says; the root Application `c1` already made (metrics-server runbook, step 1)
private-values: [k8s_gateway_zone, k8s_gateway_address]
files: [hosts/kubernetes/home/c1/apps/gateway/, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_gitops/templates/source-argocd.yaml.j2, hosts/ansible/roles/k8s_gateway/, hosts/ansible/playbooks/k8s-gateway.yml, hosts/ansible/playbooks/k8s-observability.yml]
last-tested: 2026-11-09, an agent lane on the owner's Mac, steps 1-4 on c1 at main db8b158 (diff only the ntfy routes and the namespace annotation; one hand sync, Synced and Healthy; four listeners Programmed; k8s-gateway.yml changed=2 from its smoke test only, k8s-observability.yml --tags route changed=0); autoSync on by PR after the owner's go at 06:46 UTC)
superseded-by:
---

# Move c1's Gateway and app routes from Ansible to Argo CD

Gateway `apps` in namespace `gateway` is the cluster's one way in for web traffic: HTTP on 80 and HTTPS on 443 for `*.apps.c1.prod.<zone>` and, with `shortNames`, for `*.<zone>` ([set-up-short-app-names.md](set-up-short-app-names.md)), at a fixed address from Cilium's load-balancer pool. Each app gets a route for its name, plus a second route that redirects plain HTTP to HTTPS.

The `gateway` app holds the Gateway and the routes of apps whose own charts make none (today, Grafana and ntfy: `routes` in `apps/gateway/values.yaml`). Apps with a chart of their own, such as Jellyfin, carry their routes in that chart. The node firewall ports for the listeners stay with Ansible, because they are the machines.

## What is in git

| File | What |
|---|---|
| `apps/gateway/templates/gateway.yaml` | The namespace (never deleted by Argo CD: the certificate's Secret lives there) and the Gateway, ported from `k8s_gateway`. |
| `apps/gateway/templates/routes.yaml` | One HTTPS route and one redirect route per entry in `routes`, ported from `k8s_app_route`. |
| `apps/gateway/values.yaml` | The class, the names, `https: true`, the TLS Secret, `shortNames`, and the routes list. |
| `apps/gateway/templates/name-check.yaml` | CronJob `name-check`, which opens each app's short and long name through the Gateway from inside c1 (see set-up-short-app-names.md, "Prove it from the agent box"). |
| `root/values.yaml`, entry `gateway` | Passes the zone and the Gateway's address, both private, from the root Application. |

The address and the zone are never in git. Ansible puts both into the root Application (`k8s_gitops_source_zone`, `k8s_gitops_source_gateway_address`).

## Where this stands on main

Read from `main` at `8bca3cd` on 2026-11-18; no step was run again for this page.

| Part | What main has | Still waits |
|---|---|---|
| Argo CD syncs the app | `root/values.yaml`, entry `gateway`: `wave: -1`, `autoSync: true`, `prune: false` | nothing in this repository |
| The Ansible switches | `k8s_gateway_by_argocd: false` and `k8s_observability_grafana_route_by_argocd: false` are the role defaults (`roles/k8s_gateway/defaults/main.yml`, `roles/k8s_observability/defaults/main.yml`); step 4 sets them true in the private inventory | what the private inventory holds is not readable here, so whether they are true is unproven by this page |
| Who runs the playbooks | today `k8s-gateway.yml` and `k8s-observability.yml` are not names the box's `c1-ansible` wrapper runs (its table holds `identity` only, `files/c1-ansible.sh:32`), so the Mac lane keeps the runner line. Pull request #645 (open) adds `gateway` (`k8s-gateway.yml --tags gateway`) to that wrapper; once it is merged and the box has installed it, that playbook runs from the box. `k8s-observability.yml` is not in #645 and stays on the Mac | #645's review and the box-limit install |
| The last run | `last-tested`: 2026-11-09, steps 1 to 4, four listeners Programmed, `autoSync` on by pull request | nothing on main; whether the private switches are still true is not readable here |

## Before you start

- `kubectl -n gateway get gateway apps` shows Programmed, with the address from the inventory.
- In the private inventory, `k8s_gateway_https` is true. If it is false, set `https: false` in `apps/gateway/values.yaml` by PR first.
- In the private inventory, `k8s_gitops_source_gateway_address: "{{ k8s_gateway_address }}"` is set (as in `hosts.example.yml`). Then run `ansible-playbook -i inventories/home/ playbooks/k8s-gitops.yml --tags source` so the root Application carries it. From the box, once `c1-ansible list` there prints `gitops`: `c1-ansible check gitops`, then `c1-ansible apply gitops <clearance id>`. The box runs the wrapper's fixed tags (`source,ui,sso`), which can be more than the Mac command above, and reads its own copy of the inventory ([set-up-the-agent-box.md](set-up-the-agent-box.md#change-c1-from-the-box)).
- `kubectl -n argocd get application c1` shows Synced.

Stop if any of these is not true.

## Steps

1. Refresh the root Application `c1`.
   expect: `gateway` appears, OutOfSync, automatic sync off. If it shows a render error about `address`, the root Application has no `gatewayAddress` parameter yet: go back to "Before you start".

2. Read the diff.
   ※ [spec, "Taking over a running component"](../specs/2026-11-c1-apps-under-argo-cd.md#taking-over-a-running-component-agent-pick)
   expect: tracking labels only, on the Gateway and on `grafana` and `grafana-redirect` in `monitoring`. A changed address or listener is a stop: it would move every app's traffic.

3. Sync once, by hand.
   expect: Synced and Healthy. The Gateway is still Programmed at the same address, with all its listeners Programmed (four with `shortNames`). `https://grafana.apps.c1.prod.<zone>/login` opens, and `http://` for the same name answers 301.

4. By PR, set `autoSync: true` for `gateway` in `root/values.yaml` (main already has it: entry `gateway`, `autoSync: true`, `prune: false`). In the private inventory, set `k8s_gateway_by_argocd: true` and `k8s_observability_grafana_route_by_argocd: true`. Then run `ansible-playbook -i inventories/home/ playbooks/k8s-gateway.yml` and `playbooks/k8s-observability.yml --tags route`. From the box, once `c1-ansible list` there prints `gateway`: `c1-ansible check gateway`, then `c1-ansible apply gateway <clearance id>`. The box runs the wrapper's fixed tags (`gateway`), which can be more than the Mac command above, and reads its own copy of the inventory ([set-up-the-agent-box.md](set-up-the-agent-box.md#change-c1-from-the-box)). For the route, `c1-ansible check observability`, then `apply observability <clearance id>` the same way, under the rule for `apply observability` there.
   expect: the Gateway and route apply tasks are skipped. The route play reports `changed=0`; the gateway play reports only its smoke-test app as changed (it is applied and removed on every run), still opens the firewall ports and checks the Gateway, and its smoke test passes.

## Change it

- Add a route for a new app without its own chart: add it to `routes` in `apps/gateway/values.yaml`, by PR.
- Never change the address in git: it is private. Change `k8s_gateway_address` in the inventory, then rerun the gitops source step, and update the DNS override (OPNsense) to match.

## Rebuild from nothing

The Gateway API CRDs and GatewayClass `cilium` come with Cilium (`k8s_control_plane`). Argo CD makes the Gateway (wave -1) and the routes. The firewall ports come from `k8s-gateway.yml`. The certificate comes from `k8s-certs.yml`; until it exists, the HTTPS listener is not programmed.

## If it fails

- **The way back:** delete the `gateway` Application. It has no resources finalizer, so the Gateway and the routes stay. Set both switches back to false and run both playbooks.
- Tell the owner before trying anything not written here.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.
- Add the run to the spec's decision log.

## Related

- [Spec: move c1's apps and add-ons under Argo CD](../specs/2026-11-c1-apps-under-argo-cd.md)
- [Move cert-manager on c1 from Ansible to Argo CD](move-cert-manager-to-argo-cd.md)
- `hosts/AGENT-PICKS.md` picks 142-143
