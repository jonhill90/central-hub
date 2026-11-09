---
title: Move cert-manager on c1 from Ansible to Argo CD
status: draft
kind: automated
trigger: on request (step 6 of spec 2026-11-c1-apps-under-argo-cd)
runner: an agent lane, through the owner's Mac (D-0022)
outcome: Argo CD's Application `cert-manager` is Synced and Healthy, the Gateway's certificate is still Ready, and Ansible no longer installs cert-manager
needs: the lab clone of central-hub with its private inventory; SSH to c1's control plane as D-0022 says; the root Application `c1` already made (metrics-server runbook, step 1)
private-values: [k8s_gateway_zone, k8s_certs_zone, k8s_certs_acme_email, k8s_certs_cloudflare_token_file]
files: [hosts/kubernetes/home/c1/apps/cert-manager/values.yaml, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_certs/, hosts/ansible/playbooks/k8s-certs.yml]
last-tested: not yet run on c1. CI's parity check finds the chart values the same as the role's
superseded-by:
---

# Move cert-manager on c1 from Ansible to Argo CD

cert-manager issues the Gateway's wildcard certificate (`apps-tls` in namespace `gateway`). Only cert-manager itself moves here. The ClusterIssuers, the Cloudflare token Secret and the Certificate stay with Ansible (`k8s-certs.yml`, tag `issue`), because they hold private values (the zone, the ACME email, the token). The lab PKI work (offline root, an intermediate per cluster in cert-manager) will give them their own `certs` app.

## What is in git

| File | What |
|---|---|
| `root/values.yaml`, entry `cert-manager` | Chart v1.21.3 from `https://charts.jetstack.io` (the same version as the role), wave -2, server-side apply. |
| `apps/cert-manager/values.yaml` | The role's values: CRDs installed and kept, Gateway API support on, public resolvers for the DNS-01 check. |

The role downloaded the chart file and checked it against a pinned SHA-256. Argo CD fetches it by version from the same repository and has no checksum check, so that check is lost while Argo CD installs it (pick 141).

## Before you start

- `kubectl -n gateway get certificate apps` shows Ready.
- `kubectl -n cert-manager get deploy` shows the controller, webhook and cainjector ready.
- `kubectl -n argocd get application c1` shows Synced.

Stop if any of these is not true.

## Steps

1. Refresh the root Application `c1`.
   expect: `cert-manager` appears, OutOfSync, automatic sync off.

2. Read the diff.
   expect: tracking labels and the chart's annotations only. The startupapicheck Job is a Helm hook; Argo CD runs it as a sync hook.

3. Sync once, by hand.
   expect: Synced and Healthy. `kubectl -n gateway get certificate apps` still Ready, and HTTPS on any app name still works.

4. By PR, set `autoSync: true` in `root/values.yaml`. In the private inventory, set `k8s_certs_cert_manager_by_argocd: true`, then run `ansible-playbook -i inventories/home/ playbooks/k8s-certs.yml`.
   expect: the first run deletes cert-manager's old Helm release records; the issuers, certificate and smoke test still pass; a second run reports `changed=0`.

## Change it

Raise the chart version by PR after reading the release notes. With `crds.keep: true`, removing cert-manager never removes the Certificates and Issuers.

## Rebuild from nothing

Argo CD installs cert-manager (wave -2). Then `k8s-certs.yml` makes the token Secret, the issuers and the certificate, as before. The Gateway API CRDs must exist before cert-manager starts (`k8s.yml`), or cert-manager needs a restart.

## If it fails

- **The way back:** delete the `cert-manager` Application. It has no resources finalizer, so everything stays. Set `k8s_certs_cert_manager_by_argocd: false` and run the certs playbook with `--tags certmanager`.
- Tell the owner before trying anything not written here.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.
- Add the run to the spec's decision log.

## Related

- [Spec: move c1's apps and add-ons under Argo CD](../specs/2026-11-c1-apps-under-argo-cd.md)
- `hosts/AGENT-PICKS.md` picks 138-141
