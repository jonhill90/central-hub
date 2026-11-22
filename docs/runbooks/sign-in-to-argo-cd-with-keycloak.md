---
title: Turn on sign-in to Argo CD through the lab's Keycloak
status: draft
kind: automated
trigger: on request, once realm lab has the argocd clients (Keycloak identity as code) and the Argo CD UI route is on
runner: an agent lane, through the owner's Mac (D-0022)
outcome: Argo CD's sign-in page shows "Lab sign-in"; a lab-admins member gets admin, a lab-viewers member read-only, anyone else nothing; the built-in admin still works
needs: the lab clone of central-hub with its private inventory; SSH to c1's control plane as D-0022 says; Secret argocd/argocd-sso made by playbooks/k8s-identity.yml
private-values: [k8s_gateway_zone, k8s_gitops_ui_zone]
files: [hosts/ansible/roles/k8s_gitops/files/argocd-signin-check.py, .github/hosts-check/tests/test_argocd_signin_check.sh, hosts/ansible/roles/k8s_gitops/tasks/sso.yml, hosts/ansible/roles/k8s_gitops/templates/argocd-sso.yaml.j2, hosts/ansible/roles/k8s_gitops/defaults/main.yml]
last-tested: 2026-11-18, an agent lane from the agent box, read only (c1-read, no password typed), on c1 `argocd-cm` holds `url` and `oidc.config` (issuer realm lab, clientID argocd, secret read from `argocd-sso`, the lab root as `rootCA`), `argocd-rbac-cm` holds the group table below, and `argocd-server` logs the setting sso as true. The CronJob login-probe ran inside c1 at 2026-11-18 06:11 UTC with no password and read through c1-read, Keycloak showed its sign-in page for client argocd and its redirect (HTTP 200), Argo CD listed the provider Lab sign-in and its login redirected to Keycloak realm lab. A typed sign-in, a lab-admins sign-in and step 4 not run. CI renders the manifest with sign-in on and off and checks both against the ConfigMap schema
superseded-by:
---

# Turn on sign-in to Argo CD through the lab's Keycloak

Argo CD stays installed by Ansible (D-0023 rule 2), so its sign-in settings live in the role `k8s_gitops`, tag `sso`. The role writes the keys `url` and `oidc.config` in `argocd-cm`, and `policy.csv`, `policy.default` and `scopes` in `argocd-rbac-cm`, server-side with its own field manager. So the engine's install never takes them back, and turning sign-in off removes exactly those keys.

| Realm group | Argo CD role |
|---|---|
| lab-admins | role:admin |
| lab-viewers | role:readonly |
| anyone else | nothing |

## Before you start

- `k8s_gitops_ui_route` is true, and `https://argocd.apps.c1.prod.<zone>/` opens.
- `kubectl -n argocd get secret argocd-sso` exists, labelled `app.kubernetes.io/part-of=argocd`. It comes from `playbooks/k8s-identity.yml` (realm lab as code).
- `https://sso.<zone>/realms/lab/.well-known/openid-configuration` (with short names off, `https://sso.apps.c1.prod.<zone>/realms/lab/...`; Argo CD's `k8s_gitops_sso_issuer` follows `k8s_gitops_ui_short_names`) answers from a pod in the cluster, over a certificate the pod trusts. Argo CD's server fetches it itself. With the Let's Encrypt staging certificate it can't, because staging isn't trusted: issue from production first (`k8s_certs_issuer: letsencrypt-prod`). With the lab CA (`k8s_certs_issuer: lab-ca`, D-0028), set `k8s_gitops_sso_root_ca_file` to the lab root's PEM file on the controller, and Argo CD trusts it for this sign-in only.

Stop if any of these is not true.

## Steps

1. In the private inventory, set `k8s_gitops_sso: true`. Then run `ansible-playbook -i inventories/home/ playbooks/k8s-gitops.yml --tags sso --check --diff`. From the box, once `c1-ansible list` there prints `gitops`: `c1-ansible check gitops`, then `c1-ansible apply gitops <clearance id>`. The box runs the wrapper's fixed tags (`source,ui,sso`), which can be more than the Mac command above, and reads its own copy of the inventory ([set-up-the-agent-box.md](set-up-the-agent-box.md#change-c1-from-the-box)).
   On the box, `c1-ansible` maps the inventory's `k8s_gitops_sso_root_ca_file` (a controller path) to its copy `<keys>/prod/lab-ca/root.crt`, as the prod rebuild does; before that map, `c1-ansible check gitops` stopped at `sso | The CA file is a certificate` on a path the box does not have (2026-11-22). It also passes `k8s_gitops_source_jellyfin_setup=false`, because prod is rebuilt from a restore of its own Jellyfin config (see move-jellyfin-to-argo-cd.md).
   expect: the diff adds the keys above and nothing else.

2. Run the same command without `--check`.
   expect: one change (Apply). Argo CD reads both ConfigMaps live, so no pod restarts.

3. Open Argo CD's sign-in page in a private window.
   expect: a "Lab sign-in" button. Sign in as a lab-admins member: every Application shows, and Sync works. Sign in as a lab-viewers member: Applications show, and Sync is refused.

   Scripted instead, with no browser and no owner account: `argocd-signin-check.py <file>` (`hosts/ansible/roles/k8s_gitops/files/`), run on the agent box against a test account that an access-rights step made, a member of `lab-admins` (the script needs a TOTP seed, and only that group has one). The file is JSON, held by the box, mode 0600 or 0400 and owned by the user running it: `base` (Keycloak), `argocd_base` (the host in `argocd-cm`'s `url`), `realm`, `user`, `password`, `seed`, `digits`, `period`, `expect_admin`, and optionally `admin_group`, `viewer_group`, `address`, `verify`. It follows Argo CD's own flow (`/auth/login`, Keycloak's password and then code, `/auth/callback` with the cookies from the start, the session cookie), then reads `/api/v1/session/userinfo` (logged in, Keycloak's issuer, the expected group) and `/api/v1/account/can-i/applications/sync/*/*` (yes exactly for an admin). It prints seven numbered lines and no password, seed, code, state or token. The stand-in test is `.github/hosts-check/tests/test_argocd_signin_check.sh`. It has not run against Argo CD, and a test user does not exist yet. From the box it also needs tcp 443 to the apps' address, which the firewall pass of #491 is there to give ([set-up-the-agent-box.md](set-up-the-agent-box.md), the `signin-check` paragraph).
4. Run step 2 again.
   expect: `changed=0`.

## If it fails

- **"failed to query provider"** in `kubectl -n argocd logs deploy/argocd-server`: the server can't reach or trust the issuer. Check the name from a pod, and the certificate's issuer.
- **Signed in, but sees nothing:** the token has no `groups` claim, or the group names differ from the table. Read the token's claims in Keycloak (Clients, argocd, Client scopes, Evaluate).
- **The way back:** set `k8s_gitops_sso: false` and run step 2. The keys are removed, and only the built-in admin can sign in (`argocd-initial-admin-secret`, or the password the owner set).
- Tell the owner before trying anything not written here.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.

## Related

- `docs/decisions/0023-use-argo-cd-as-the-gitops-engine.md`
- `hosts/AGENT-PICKS.md` pick 170
