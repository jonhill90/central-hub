---
title: Run Home Assistant on c1 and sign in with Keycloak
status: draft
kind: automated
trigger: after a change to Home Assistant's chart (`hosts/kubernetes/home/c1/apps/home-assistant/`), its Keycloak client, or its image or sign-in component pin; and as part of every c1 rebuild
runner: an agent lane; Argo CD does the app, the box's `c1-ansible` adds the client
outcome: the first-run screen is closed by the setup Job before the route opens; then https://homeassistant.<zone>/ shows Home Assistant, its sign-in page offers "Hub sign-in" through realm lab, and a lab-admins account becomes an administrator
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
| The image, pinned by tag and digest (2026.7.4, the last release before 2026.8, STD-0003; held back on purpose, see "If it fails") | `apps/home-assistant/values.yaml`, `image` |
| Sign-in: the custom component hass-oidc-auth 1.2.1 (MIT), copied into `/config/custom_components` by an init container from a sha256-checked archive | `values.yaml`, `sso.plugin` |
| `configuration.yaml`, written on every start from a ConfigMap: proxy trust, the `auth_oidc` block, the three UI files | `templates/configmap.yaml` |
| The client `homeassistant`: public, PKCE S256, redirect `https://<name>/auth/oidc/callback` for the short and the long name. Public, so no secret exists | `realm.yaml.j2` |
| The first-run owner: a fresh Home Assistant makes whoever reaches its first-run screen first the owner. A CronJob (`homeassistant-setup`, every 5 minutes) creates the owner through the onboarding API from inside the cluster, with a password made in the cluster by an External Secrets generator (made once, in every cluster, whatever store the other apps use, so a missing OpenBao key can never leave the Job waiting), so no person types it | `templates/setup-*.yaml`, `files/setup.sh` |
| The route: **off** (`route.enabled: false`) on a new install, so the name serves nothing until the screen is closed | `values.yaml`, `route.enabled` |
| Who may open it: realm group `lab-admins` becomes a Home Assistant administrator, everyone else who signs in becomes a user (the user role is left unset, so nobody gets the plugin's "invalid" role). Home Assistant applies the role only when it first creates the person: someone created earlier keeps their role until changed in Settings > People | `values.yaml`, `sso.adminGroup`, `sso.userGroup` |
| Keycloak's certificate trust: a small cert-manager Certificate on `lab-ca` whose `ca.crt` the component reads (`network.tls_ca_path`) | `templates/lab-ca.yaml` |

## Why no host network

Home Assistant finds devices by multicast (mDNS, SSDP). That does not cross VLANs, and c1's nodes are on VLAN 10, so host networking would give discovery on the wrong network and loosen the pod's isolation for nothing. Devices are added by address in the UI (Settings, Devices and services). If a device ever needs multicast on its own VLAN, the way to get it is a second pod or a small relay on that VLAN, not host networking on c1.

## Why the route starts off

Home Assistant's first-run screen has no password: the first visitor creates the owner. The pod is up as soon as Argo CD syncs it, and the route and the name would put it on the network. So the route ships off, and the order is: pod up, setup Job closes the screen, a check says so, then the route opens. Until then only pods inside c1 can reach the pod; the Job runs every 5 minutes, so that window is at most one tick after the pod is ready.

## Steps

1. On a rebuild, nothing to do: the `apps` stage syncs the app; the `identity` stage imports the realm with the client. The route is off, so a rebuilt c1 comes back with Home Assistant closed to the network until step 5.
2. On a live c1, add the client without ending any session. From the agent box, once the box has installed this change: `c1-ansible check clients`, then `c1-ansible apply clients <clearance id>`.
   why: a realm replace ends every open sign-in. The wrapper's client list now has `homeassistant`.
   expect: `client homeassistant: ok`, `failed=0`.
3. The names: `homeassistant.apps.c1.prod.<zone>` resolves through the wildcard at once. The short name `homeassistant.<zone>` needs the firewall's Unbound override (`opnsense-prod`) and the tailnet's split-DNS entry (`tailnet-stack`), both lists changed in this pull request ([set-up-short-app-names.md](set-up-short-app-names.md)).
4. Check the first-run screen is closed: the newest setup Job's log prints `PASS: onboarding user step done by the setup job` (or `already done, and the Secret's owner password is accepted`; `already done` alone is not a pass, and a `FAIL` that says the password is refused means someone else made the owner): `c1-read logs -n home job/<newest homeassistant-setup job>`. The Job also finishes the core config, analytics and integration steps, so the first sign-in lands on the dashboard (only steps still open are called, and only then does the Job sign in for a token, so a finished system makes no new tokens; a refused step prints a `note:` line and the Job still prints `PASS` for the user step). A `FAIL` line means the screen may still be open: leave the route off and read the line.
   expect: `PASS`. The Job runs every 5 minutes, so a new log appears within 5 minutes of the apply.
5. Open the route, in its own pull request: set `route.enabled: true` in the chart values. Then `openbao-prod adopt` copies the owner's password (Secret `homeassistant-owner` in namespace `home`) into OpenBao key `c1/homeassistant-owner` and the SOPS copy, from its fixed table, once the box has installed the row ([set-up-the-secrets-store.md](set-up-the-secrets-store.md)). Until that is done a rebuild makes a new owner password, which only matters if Home Assistant's volume is restored from a backup that holds the old one.
   why: the route is the only thing that exposes the app, and the password must outlive a teardown.
6. Prove it from the box, no password: `curl -s -o /dev/null -w '%{http_code}' https://homeassistant.apps.c1.prod.<zone>/manifest.json` is 200; `curl -s https://homeassistant.apps.c1.prod.<zone>/auth/oidc/welcome` shows the sign-in welcome page; its redirect goes to `https://sso.<zone>/realms/lab/protocol/openid-connect/auth?...client_id=homeassistant...code_challenge_method=S256`.
7. A typed sign-in is the owner's: open the address, choose "Hub sign-in", sign in, and Home Assistant's first-run screen (or its dashboard) opens.

## If it fails

- **Pod stuck at the init container:** `c1-read logs -n home deploy/homeassistant -c install-sso`; a `sha256sum` failure means the archive changed, so check the pin.
- **Sign-in page has no "Hub sign-in":** the component did not load; `c1-read logs -n home deploy/homeassistant` and look for `auth_oidc`. A wrong discovery URL or a certificate error names itself there.
- **Keycloak says "Invalid parameter: redirect_uri":** the client is not in the live realm yet; run step 2.
- **400 on every request:** the proxy is not trusted. On 2026.8 and later the `http:` block in configuration.yaml is not applied (the settings live in the UI, and a change is dropped unless an admin confirms it within 5 minutes; official page: [HTTP integration](https://www.home-assistant.io/integrations/http/)), so the chart holds the image at 2026.7.4. On 2026.7.4 the other cause is the Gateway's source address being outside `trustedProxies`. The YAML block stops working in 2027.2, so the pin has to move before then.
- **The route is on and the setup Job says FAIL:** set `route.enabled: false` at once and sync, then read the Job log.
- **The setup Job said `FAIL: onboarding endpoint did not answer` after Home Assistant restarted:** once every onboarding step is done, Home Assistant serves no onboarding API at its next start, so the status read gets HTTP 404 (`homeassistant/components/onboarding/__init__.py`, `async_setup`). The script now treats 404 as all steps done and still checks the owner password; any other HTTP code prints `FAIL: onboarding endpoint answered HTTP <code>`. First seen 2026-11-24 after the worker restart.
- **`UnsupportedStorageVersionError: Storage file http has version 3 which is newer than the max supported version 1` and the pod crash-loops:** the volume was written by a newer Home Assistant than the image. Home Assistant does not step back over its storage files. Give the chart a new claim name (`storage.claimName`) so the setup Job onboards a fresh Home Assistant; the old claim is kept and unused, and the owner password Secret is unchanged.
- **The way back:** set `sso.enabled: false` in the chart values and sync; Home Assistant's own login (the first user made at first run) then stands alone.

## Not covered yet

- Backup of the volume: **not proven.** The claim `homeassistant-data` is on the default StorageClass (local-path) like Jellyfin's, and the c1 restic job backs up the whole local-path folder on each node (`c1-backup-volumes.sh`, `BACKUP_VOLUME_PATHS`), so it should already be in the nightly snapshot. The claim was made after the last nightly run (2026-11-23 02:29 UTC), so no snapshot holds it yet; the first one expected is the 2026-11-24 02:29 UTC run, and the restore test covers only Jellyfin's claim. Until a listing shows `home/homeassistant-data`, treat it as not backed up; Home Assistant's own backups (Settings, System, Backups) are the manual interim.
- A person signing in through Keycloak creates a second Home Assistant user, mapped by group; the local `owner` account made by the setup Job stays as the break-glass login, its password in OpenBao.
- Live proof of sign-in: the agent box's scripted browser check (run 2026-11-23 07:20 UTC, reported by the agent lane that ran it) passed Home Assistant, ending at the dashboard, after the setup Job had finished onboarding (status read: user, core_config, analytics and integration all done). The setup script's steps were tested on a mock; which run completed them on the live system was not recorded.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.

## Related

- [Set up sign-in for lab apps on c1](set-up-lab-sign-in.md)
- [Move Jellyfin to Argo CD](move-jellyfin-to-argo-cd.md)
