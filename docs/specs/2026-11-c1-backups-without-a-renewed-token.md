---
title: Let c1's backups sign in to Azure with c1's own service-account tokens, so nothing has to renew a token
status: proposed
date: 2026-11-09
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Let c1's backups sign in to Azure with c1's own service-account tokens, so nothing has to renew a token

## What and why

c1's restic backups reach Azure Blob with a user delegation SAS. Azure caps that kind of SAS at 7 days, so someone has to mint a new one every few days. The first plan had an agent lane do it, and on 2026-11-09 the owner ruled that out: an agent never stands in for a deterministic process. A timer that mints the SAS would itself need a stored Azure credential, which goes against the owner's request of 2026-11-08 for no raw keys. This change removes the SAS so nothing has to renew anything.

The mechanism is Microsoft Entra workload identity federation:

1. **c1 becomes a public token issuer.** The API server already signs service-account tokens. It gets a public issuer URL, `--service-account-issuer`, and the issuer's discovery document and public keys are published at that URL. Only public keys go out.
2. **A user-assigned managed identity trusts that issuer.** The identity is free, and it trusts the issuer for one subject, `system:serviceaccount:c1-backup:restic`, with audience `api://AzureADTokenExchange`. It holds Storage Blob Data Contributor on the backup storage account only. It is built in `hosts/terraform/azure/backup`, next to the account.
3. **Each node has a holder pod.** A DaemonSet runs one small pod per node under service account `restic`, with a projected token volume for that audience and a lifetime of 24 hours. The kubelet writes the token to the pod's volume on the node and refreshes it before it expires.
4. **The backup scripts use that token.** The nodes' systemd timers stay, as pick 145 set out. Each script finds the holder pod's token file on its node and runs restic with three settings:
   - `AZURE_CLIENT_ID`, the identity's client ID, which is not a secret
   - `AZURE_TENANT_ID`
   - `AZURE_FEDERATED_TOKEN_FILE`

   restic 0.19.1 signs in through Azure's default credential chain when no key or SAS is set, so restic needs no change.
5. **The SAS code goes.** The `az storage container generate-sas` step, `k8s_backup_azure_sas` and the SAS lines in the nodes' env file are all removed.

This serves the PRD's goal that every piece can be rebuilt from the repository and swapped, and it closes TASK-0202 and the credential question in D-0033.

### Agent picks

- **A holder pod, not backups as pods.** Restic stays in systemd timers on the nodes. That way a backup still runs if the cluster is unhealthy, because the last token stays valid for up to 24 hours. Running restic as CronJobs was the other option.
- **The old issuer is kept as a second value.** The API server gets the public issuer first and the default `https://kubernetes.default.svc.cluster.local` second. Tokens issued before the change stay valid, and kubeadm `ClusterConfiguration.apiServer.extraArgs` takes repeated flags.
- **The signing key survives a rebuild.** The service-account signing key (`/etc/kubernetes/pki/sa.key`) is already in the nightly etcd bundle (pick 147). A rebuild that restores it keeps the published keys valid. A rebuild that doesn't must publish the new keys before the first backup.

## Out of scope

- Sign-in to apps with Microsoft Entra upstream of Keycloak (TASK-0200).
- Any other workload's Azure access.
- Deletion protection and the access tier for the backups. Those choices stay in D-0033.

## Acceptance criteria

### Automated

- [ ] `.github/hosts-check/run.sh terraform`: the backup run folder's tests cover these:
  - the identity exists
  - the federated credential names the issuer, subject and audience above
  - the role is on the storage account only
- [ ] `.github/hosts-check/run.sh backup`: the scripts find a token file laid out as the kubelet writes it, and fail with a clear error when it is missing.
- [ ] `.github/hosts-check/run.sh ansible`: no task in the role calls `az` any more.

### Manual (what the owner checks)

- [ ] The playbook's `drill` tag passes on c1, and the nodes' env file holds no SAS.
- [ ] The issuer URL serves `/.well-known/openid-configuration` and `/openid/v1/jwks`, and holds public keys only.
- [ ] Seven days after the switch, the nightly backups are still running with no agent or person having touched them.

## Points to (read when)

- [D-0033](../decisions/0033-keep-c1-off-box-backups-in-azure-blob-with-restic.md): read for the backup target and what stays open there.
- [back-up-c1-off-box.md](../runbooks/back-up-c1-off-box.md): read before changing the role or the run folder. Steps A1 to A4 change with this work.
- [give-agents-access-to-azure.md](../runbooks/give-agents-access-to-azure.md): read for the agents' service principal, which applies the run folder.

## Decision log

- 2026-11-09: drafted after the owner ruled out agent renewals (06:50 UTC). The owner chooses the identity on a decision card in the backups thread. Federation is the drafting agent's recommendation. Azure Arc on the nodes was weighed: its supported list has AlmaLinux 8 and 9 but not 10, which c1 runs, and its agent is closed source. A service principal certificate was also weighed, but it is a long-lived secret that expires.
- 2026-11-09, 07:07 UTC: the owner left the choice between this and a service principal certificate to the agents, asked for a deterministic process, and asked for a revisit to be backlogged. The agents built the certificate, which each node makes and rolls itself (pick 189 in `hosts/AGENT-PICKS.md`). This spec stays proposed as the design to look at again in TASK-0223.
- Open, for the owner: where the issuer documents are served. They need a stable public HTTPS name that Entra ID can reach. Two candidates:
  - a static page under the owner's DNS zone
  - the repository's GitHub Pages site

  The name is baked into every token and into the federated credential, so changing it later means a coordinated change on both sides.
