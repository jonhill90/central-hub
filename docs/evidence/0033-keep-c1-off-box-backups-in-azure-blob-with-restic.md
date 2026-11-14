---
record: D-0033
batch: RB-0026 (off-site backup target and restore test), with the FOSS check RB-0208 for the licences
researched: 2026-10-16 to 2026-11-14
method: on 2026-10-16, Azure prices read from the Azure Retail Prices API and each provider's documentation and pricing pages read; on 2026-11-14, restic's and s3proxy's licence files read from their repositories, central-hub searched for every file naming Azure, and the S3 question checked by web search, GitHub issue search and the Microsoft Learn docs
checks: "RB-0026 had an independent review on 2026-10-16: PASS after fixes, with every fix applied. RB-0208 had no independent check"
---

# Evidence for D-0033: c1's off-box backups in Azure Blob with restic

This file summarises the research behind D-0033. It adds nothing the research did not find. RB-0026 was asked about off-site etcd snapshots for a single-node cluster on a VPS. D-0033 uses its comparison of targets and tools for c1's backups, which also hold volume folders.

## Question

Where should off-site backups go, with which tool, and with which credential, so that the cluster can be rebuilt after its host is lost? Is the chosen target free software, and what is the way out?

## Findings

1. **Targets compared.** Azure Blob, Cloudflare R2, Backblaze B2, AWS S3 and a home or tailnet machine were set side by side on price, restore egress, minimum retention, encryption, least-privilege credential, short-lived credential, immutability, API and exit path [1] (sourced and measured).
2. **Cost does not separate them** at the size studied: under 2 GB costs about 0.02 USD a month on Azure Cool and fits the free tiers of R2 and B2 [1] (inferred from the measured prices). Azure Blob in West Europe, LRS: Hot 0.0196 and Cool 0.01 USD per GB-month; the first 100 GB of internet egress a month free, then 0.08 USD per GB [2] (measured, 2026-10-16). Cool and Cold charge for early deletion before 30 and 90 days [3] (sourced).
3. **Encryption.** Azure Storage encrypts all data at rest with AES-256-GCM, and this cannot be turned off [4] (sourced). Provider encryption uses keys the provider holds, so the copy is encrypted on the host before upload; restic does this [1] (inferred).
4. **Least privilege.** Azure data roles can be scoped to one container, Shared Key access can be disallowed, and blob delete is its own data action, so a custom role or a role condition can allow write without delete [5] (sourced).
5. **Immutability.** A locked time-based retention policy cannot be deleted or shortened, and blocks container and account deletion [6] (sourced). Blob soft delete keeps deleted or overwritten blobs for 1 to 365 days, but does not protect against container or account deletion [7] (sourced).
6. **A credential with no script-held secret.** An Azure Arc-enabled server gets a managed identity whose tokens the script requests locally, but the agent's certificate on disk is itself a credential that can request tokens [8] (sourced). Whether workload identity federation works for a cluster with no public OIDC issuer was not researched [1].
7. **Exit path.** Microsoft's introduction to Blob Storage lists its ways in as the Azure Storage REST API, client libraries, SFTP and NFS 3.0, and names no S3 API [13] (sourced). The accepted answer on Microsoft's Q&A site says there is no official S3 support for Blob Storage in Microsoft's SDKs and points to s3proxy [14] (sourced; a community answer). S3 clients reach Blob Storage through a gateway such as s3proxy, Apache-2.0 [15] (measured), or a paid one sold on the Azure Marketplace [16] (sourced). A GitHub issue search of the Azure organisation found no request for a native S3 endpoint [11] (measured). Not tested hands-on. restic's backends include local disk, SFTP, a REST server, S3 and S3-compatible stores, B2, Azure Blob and any rclone remote, and `restic copy` moves snapshots between repositories [9] (sourced). rclone copies a backup set between Azure Blob, B2, S3, R2 and SFTP [10] (sourced).
8. **Licences.** Azure is a closed, paid service [11] (sourced). restic is BSD-2-Clause [12] (measured), and its REST server, a free target to move to, is BSD-2-Clause [11] (measured).
9. **Reach.** 34 files in 8 folders of `hosts/`, 11 runbooks and D-0033 name Azure [11] (measured, 2026-11-14).

## How the decision used it

(Written from the record, not from the batch.)

- Finding 1 lists the targets behind options 2 and 3. Option 1's target is the owner's pick of 2026-10-16, made from this comparison.
- Findings 3 and 4 back rules 1 and 2: encrypt on the node, no account key, a role scoped to the container.
- Finding 5 is the "protection against deletion" item under Not decided here.
- Finding 6 is the "credential with no key on the node" item, left to TASK-0224.
- Findings 7 and 8 are the exit path.
- Finding 2 is background only. The record's Cost table is its own read of 2026-11-09, for East US 2.

## Limits

- RB-0026 compared targets for etcd snapshots on a VPS, not c1's volumes, and measured no snapshot size.
- Its prices are West Europe list prices of 2026-10-16.
- Velero's limit with hostPath volumes (option 4) comes from agent pick 144, not this batch.
- Garage's licence was not fetched in RB-0208, so no S3-compatible self-hosted store was checked as a target.
- RB-0208's licence lines and its S3 check had no independent check.
- Whether the lab's storage account answers S3 requests was not tested hands-on.

## References

Relied on (the decision depends on these):

1. RB-0026 synthesis and ledger (Research repository, batch `0026-etcd-backup`).
2. Azure Retail Prices API, Storage and Bandwidth meters, West Europe, fetched 2026-10-16. <https://prices.azure.com/api/retail/prices>
3. Microsoft Learn, "Access tiers for blob data". <https://learn.microsoft.com/azure/storage/blobs/access-tiers-overview>
4. Microsoft Learn, "Azure Storage encryption for data at rest". <https://learn.microsoft.com/en-us/azure/storage/common/storage-service-encryption>
5. Microsoft Learn, "Assign an Azure role for access to blob data". <https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access>
6. Microsoft Learn, "Store business-critical blob data with immutable storage". <https://learn.microsoft.com/azure/storage/blobs/immutable-storage-overview>
7. Microsoft Learn, "Soft delete for blobs". <https://learn.microsoft.com/azure/storage/blobs/soft-delete-blob-overview>
8. Microsoft Learn, "Authenticate against Azure resources with Azure Arc-enabled servers". <https://learn.microsoft.com/azure/azure-arc/servers/managed-identity-authentication>
9. restic, "Working with repositories". <https://restic.readthedocs.io/en/stable/045_working_with_repos.html>
10. rclone, "Overview of cloud storage systems". <https://rclone.org/overview/>
11. RB-0208 findings (Research repository, batch `foss-check`): Azure's line, the rest-server licence, the repository search of central-hub at 5626e8e, and section 7 (the S3 check).
12. restic LICENSE. <https://raw.githubusercontent.com/restic/restic/master/LICENSE>
13. Microsoft Learn, "Introduction to Azure Blob Storage". <https://learn.microsoft.com/azure/storage/blobs/storage-blobs-introduction>
14. Microsoft Q&A, "S3 API support over Azure Blob Storage?". <https://learn.microsoft.com/en-us/answers/questions/1183760/s3-api-support-over-azure-blob-storage>
15. s3proxy README and LICENSE. <https://github.com/gaul/s3proxy>
16. Azure Marketplace, "Flexify.IO". <https://marketplace.microsoft.com/en-us/product/virtual-machines/flexify.azure-s3-api>

The batches' working files are private.
