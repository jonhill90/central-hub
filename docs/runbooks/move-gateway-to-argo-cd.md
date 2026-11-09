---
title: Move c1's Gateway and app routes from Ansible to Argo CD
status: draft
kind: automated
trigger: on request (step 9 of spec 2026-11-c1-apps-under-argo-cd)
runner: an agent lane, through the owner's Mac (D-0022)
outcome: Argo CD's Application `gateway` is Synced and Healthy, Gateway `apps` keeps its address and both listeners, Grafana still opens over HTTPS, and Ansible no longer applies the Gateway or Grafana's route
needs: the lab clone of central-hub with its private inventory; SSH to c1's control plane as D-0022 says; the root Application `c1` already made (metrics-server runbook, step 1)
private-values: [k8s_gateway_zone, k8s_gateway_address]
files: [hosts/kubernetes/home/c1/apps/gateway/, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_gitops/templates/source-argocd.yaml.j2, hosts/ansible/roles/k8s_gateway/, hosts/ansible/playbooks/k8s-gateway.yml, hosts/ansible/playbooks/k8s-observability.yml]
last-tested: not yet run on c1. CI's parity check finds the Gateway (HTTPS on) and Grafana's routes the same as the roles render them
superseded-by:
---

# Move c1's Gateway and app routes from Ansible to Argo CD

Gateway `apps` in namespace `gateway` is the cluster's one way in for web traffic: HTTP on 80 and HTTPS on 443 for `*.apps.c1.prod.<zone>`, at a fixed address from Cilium's load-balancer pool. Each app gets a route for its name, plus a second route that redirects plain HTTP to HTTPS.

The `gateway` app holds the Gateway and the routes of apps whose own charts make none (today, Grafana). Apps with a chart of their own, such as Jellyfin, carry their routes in that chart. The node firewall ports for the listeners stay with Ansible, because they are the machines.

## What is in git

| File | What |
|---|---|
| `apps/gateway/templates/gateway.yaml` | The namespace (never deleted by Argo CD: the certificate's Secret lives there) and the Gateway, ported from `k8s_gateway`. |
| `apps/gateway/templates/routes.yaml` | One HTTPS route and one redirect route per entry in `routes`, ported from `k8s_app_route`. |
| `apps/gateway/values.yaml` | The class, the names, `https: true`, the TLS Secret, and the routes list. |
| `root/values.yaml`, entry `gateway` | Passes the zone and the Gateway's address, both private, from the root Application. |

The address and the zone are never in git. Ansible puts both into the root Application (`k8s_gitops_source_zone`, `k8s_gitops_source_gateway_address`).

## Before you start

- `kubectl -n gateway get gateway apps` shows Programmed, with the address from the inventory.
- In the private inventory, `k8s_gateway_https` is true. If it is false, set `https: false` in `apps/gateway/values.yaml` by PR first.
- In the private inventory, `k8s_gitops_source_gateway_address: "{{ k8s_gateway_address }}"` is set (as in `hosts.example.yml`). Then run `ansible-playbook -i inventories/home/ playbooks/k8s-gitops.yml --tags source` so the root Application carries it.
- `kubectl -n argocd get application c1` shows Synced.

Stop if any of these is not true.

## Steps

1. Refresh the root Application `c1`.
   expect: `gateway` appears, OutOfSync, automatic sync off. If it shows a render error about `address`, the root Application has no `gatewayAddress` parameter yet: go back to "Before you start".

2. Read the diff.
   ※ [spec, "Taking over a running component"](../specs/2026-11-c1-apps-under-argo-cd.md#taking-over-a-running-component-agent-pick)
   expect: tracking labels only, on the Gateway and on `grafana` and `grafana-redirect` in `monitoring`. A changed address or listener is a stop: it would move every app's traffic.

3. Sync once, by hand.
   expect: Synced and Healthy. The Gateway is still Programmed at the same address. `https://grafana.apps.c1.prod.<zone>/login` opens, and `http://` for the same name answers 301.

4. By PR, set `autoSync: true` for `gateway` in `root/values.yaml`. In the private inventory, set `k8s_gateway_by_argocd: true` and `k8s_observability_grafana_route_by_argocd: true`. Then run `ansible-playbook -i inventories/home/ playbooks/k8s-gateway.yml` and `playbooks/k8s-observability.yml --tags route`.
   expect: both report `changed=0`. The gateway play still opens the firewall ports and checks the Gateway; its smoke test still passes.

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
