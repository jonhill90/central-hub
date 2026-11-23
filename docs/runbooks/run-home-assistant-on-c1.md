---
title: Run Home Assistant on c1 and sign in with Keycloak
status: draft
kind: automated
trigger: after a change to Home Assistant's chart (`hosts/kubernetes/home/c1/apps/home-assistant/`), its Keycloak client, or its image or sign-in component pin; and as part of every c1 rebuild
runner: an agent lane; Argo CD does the app, the box's `c1-ansible` adds the client
outcome: opening https://homeassistant.<zone>/ (or https://homeassistant.apps.c1.prod.<zone>/) shows Home Assistant, and its sign-in page offers "Lab sign-in" through realm lab; a lab-admins account becomes an administrator
needs: Argo CD app `home-assistant` (namespace `home`), cert-manager ClusterIssuer `lab-ca`, realm lab with client `homeassistant`, the Gateway `apps`
private-values: [k8s_gitops_source_zone]
files: [hosts/kubernetes/home/c1/apps/home-assistant/, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_identity/templates/realm.yaml.j2, hosts/ansible/roles/agent_box/files/c1-ansible.sh]
last-tested: not yet; written with the pull request that adds it
superseded-by:
---

# Run Home Assistant on c1 and sign in with Keycloak

Home Assistant (Apache-2.0) runs as the container install: one pod in namespace `home`, one 5 Gi volume for `/config`, a Service and a Gateway route. It is an Argo CD app like Jellyfin, from a chart in this repository.

| What | Where it comes from |
|---|---|
| The image, pinned by tag and digest (2026.11.1, 14 days old on 2026-11-23, STD-0003) | `apps/home-assistant/values.yaml`, `image` |
| Sign-in: the custom component hass-oidc-auth 1.2.1 (MIT), copied into `/config/custom_components` by an init container from a sha256-checked archive | `values.yaml`, `sso.plugin` |
| `configuration.yaml`, written on every start from a ConfigMap: proxy trust, the `auth_oidc` block, the three UI files | `templates/configmap.yaml` |
| The client `homeassistant`: public, PKCE S256, redirect `https://<name>/auth/oidc/callback` for the short and the long name. Public, so no secret exists | `realm.yaml.j2` |
| Who may open it: realm group `lab-admins` becomes a Home Assistant administrator, `lab-viewers` a user, anyone else is refused | `values.yaml`, `sso.adminGroup`, `sso.userGroup` |
| Keycloak's certificate trust: a small cert-manager Certificate on `lab-ca` whose `ca.crt` the component reads (`network.tls_ca_path`) | `templates/lab-ca.yaml` |

## Why no host network

Home Assistant finds devices by multicast (mDNS, SSDP). That does not cross VLANs, and c1's nodes are on VLAN 10, so host networking would give discovery on the wrong network and loosen the pod's isolation for nothing. Devices are added by address in the UI (Settings, Devices and services). If a device ever needs multicast on its own VLAN, the way to get it is a second pod or a small relay on that VLAN, not host networking on c1.

## Steps

1. On a rebuild, nothing to do: the `apps` stage syncs the app; the `identity` stage imports the realm with the client.
2. On a live c1, add the client without ending any session. From the agent box, once the box has installed this change: `c1-ansible check clients`, then `c1-ansible apply clients <clearance id>`.
   why: a realm replace ends every open sign-in. The wrapper's client list now has `homeassistant`.
   expect: `client homeassistant: ok`, `failed=0`.
3. The names: `homeassistant.apps.c1.prod.<zone>` resolves through the wildcard at once. The short name `homeassistant.<zone>` needs the firewall's Unbound override (`opnsense-prod`) and the tailnet's split-DNS entry (`tailnet-stack`), both lists changed in this pull request ([set-up-short-app-names.md](set-up-short-app-names.md)).
4. Prove it from the box, no password: `curl -s -o /dev/null -w '%{http_code}' https://homeassistant.apps.c1.prod.<zone>/manifest.json` is 200; `curl -s https://homeassistant.apps.c1.prod.<zone>/auth/oidc/welcome` shows the sign-in welcome page; its redirect goes to `https://sso.<zone>/realms/lab/protocol/openid-connect/auth?...client_id=homeassistant...code_challenge_method=S256`.
5. A typed sign-in is the owner's: open the address, choose "Lab sign-in", sign in, and Home Assistant's first-run screen (or its dashboard) opens.

## If it fails

- **Pod stuck at the init container:** `c1-read logs -n home deploy/homeassistant -c install-sso`; a `sha256sum` failure means the archive changed, so check the pin.
- **Sign-in page has no "Lab sign-in":** the component did not load; `c1-read logs -n home deploy/homeassistant` and look for `auth_oidc`. A wrong discovery URL or a certificate error names itself there.
- **Keycloak says "Invalid parameter: redirect_uri":** the client is not in the live realm yet; run step 2.
- **400 on every request:** the proxy is not trusted; the Gateway's source address is outside `trustedProxies`.
- **The way back:** set `sso.enabled: false` in the chart values and sync; Home Assistant's own login (the first user made at first run) then stands alone.

## Not covered yet

- Backup of the volume: it is a kept claim on local-path; the c1 restic job does not yet include namespace `home`. Home Assistant's own backups (Settings, System, Backups) are the interim.
- The first-run user: Home Assistant makes its owner account on the first visit, before or after SSO. With `lab-admins` mapped, the first OIDC login becomes an administrator.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.

## Related

- [Set up sign-in for lab apps on c1](set-up-lab-sign-in.md)
- [Move Jellyfin to Argo CD](move-jellyfin-to-argo-cd.md)
