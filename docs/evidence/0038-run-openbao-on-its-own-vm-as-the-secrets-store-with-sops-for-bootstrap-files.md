---
record: D-0038
batch: RB-0209 (2026-11-14), with RB-0012 (2026-10-14) behind it
researched: 2026-11-14
method: OpenBao v2.7.2, SOPS v3.13.3, the SOPS docs site and External Secrets v2.14.0 cloned at those tags and their licence files and docs read; release dates read from the tags; nothing run yet
checks: none independent yet; the reviewing agent checks the record against this file before any merge, and the dev build in the record's Confirmation measures findings 7 to 14
---

# Evidence for D-0038: OpenBao and SOPS as the lab's secrets store

This file summarises the research behind D-0038. It adds nothing the research did not find. Nothing here has been run on the lab yet: the seal, restore and login findings are what the projects' own docs say, and the dev build measures them before prod.

## Question

Is OpenBao free software with no paid edition, and how should the lab run it so that it unseals with no person, is backed up and restored, feeds External Secrets on c1 and the agent box's jobs, and has a break-glass path? What does SOPS add, and how does it fit the owner's earlier "no SOPS" and "no ciphertext in the repository"?

## Findings

1. **OpenBao is MPL-2.0** [1], a Linux Foundation project whose charter says all outbound code is made available under that licence [2] (sourced).
2. **No paid edition of OpenBao** appears in its docs. Its only "Enterprise" mentions are about compatibility with another vendor's paid product, and it re-implements features that vendor sells, such as namespaces, in the open project [3] (sourced; "no paid edition" inferred from findings 1 and 2).
3. **OpenBao's seal plugins are MPL-2.0** too [4] (sourced).
4. **SOPS is MPL-2.0** and a CNCF Sandbox project [5]; **age is BSD-3-Clause** [6]; **External Secrets is Apache-2.0** [7]. No paid edition of SOPS or age was found (sourced; inferred for the editions).

5. The newest OpenBao release at least two weeks old on 2026-11-14 is **2.7.2**, tagged 2026-10-26; for SOPS it is **3.13.3**, tagged 2026-07-23 (measured from the tags).
6. OpenBao ships an RPM with a checksum file and signatures for each release [8] (sourced).

7. **With no seal set, OpenBao uses Shamir and needs a person to unseal every start**; its docs call scripting that "a discouraged pattern" and point to the static key seal [9] (sourced).
8. **The static key seal is built in**: a 32-byte key from a file, with current and previous key IDs for rotation. The docs ask operators to "carefully evaluate" it and recommend it when another source of trust holds the key [10] (sourced).
9. **Built in from 2.7:** static, transit and KMIP. **Plugins:** PKCS#11, Azure Key Vault and the other cloud KMS seals [11] (sourced).
10. **With any auto-unseal, losing the seal key loses the data**, "even from backups"; recovery keys can't decrypt the root key [12] (sourced).
11. **Seal migration** between seal types is supported, with both seals available, a backup first and brief downtime [12] (sourced). This is the record's exit path.
12. **Self-initialization** sets up audit, mounts, auth and policies on first start with no person. It needs an auto-unseal, makes no recovery keys and revokes its root token [13]. Recovery keys are made later through `sys/rotate/recovery`, and the docs warn to make them well before they are needed [12] (sourced).

13. **Raft snapshots** are saved and restored with `bao operator raft snapshot`. A restore checks the snapshot against the seal keys, and a forced restore skips that check [14] (sourced).

14. **External Secrets reaches OpenBao through its HashiCorp Vault provider**, which it rates stable. Its own OpenBao page is rated alpha, with one named maintainer, and says it was tested with External Secrets 0.16.1 and OpenBao 2.2.0 [15] (sourced). The Kubernetes provider c1 uses today is rated beta [15].
15. **The Vault provider logs in by AppRole, Kubernetes, JWT or TLS certificate** [15] (sourced).
16. **JWT auth can check a cluster's service-account tokens offline** against the cluster's public key, with no call to the cluster. It does not ask Kubernetes whether a token was revoked, so a revoked token works until it expires; the docs advise short-lived tokens [16] (sourced).
17. **Kubernetes auth from outside the cluster** can use each client's own token to ask Kubernetes, with no stored reviewer token, if each client has `system:auth-delegator` [17] (sourced).
18. A rebuilt cluster gets a new service-account key from kubeadm (model; not opened this session).

19. **SOPS can encrypt with age, PGP, cloud KMS, or OpenBao's transit engine** [5] and [18] (sourced).
20. **SOPS keeps key names in clear text** and encrypts the values [19] (sourced).
21. **Any one recipient decrypts a SOPS file by default**; key groups can require more than one [20] (sourced).

22. The private files a rebuild needs live on the controller only, "not in a password manager and not in git" [21] (sourced).
23. The agent box keeps keys in `/etc/agent-keys`, owned by user `keys`, used only by its wrappers [22] (sourced).
24. c1's secret keys are named `<app>-<field>` so each maps to one vault entry [23] (sourced).

25. **A store can run with no recovery shares.** With an auto-unseal seal, `recovery_shares` may be 0 (since v2.4.0); no recovery keys are made, they can be made later through the rotate endpoint, and "Recovery mode will not function until such keys are created" [24]. Self-initialization makes none [13] (sourced; added 2026-11-14 for the edit of rules 4 and 5, batch RB-0228).
26. **Rotating a static key with no recovery key can fail.** OpenBao issue #3996 reports that after a static key rotation the server could not unseal once the old key was removed, because the key upgrade stopped at "no recovery key found" [25]. Two commenters disagree on whether that is a bug: satoqz wrote "this is very niche but I suppose it's still a bug" and "I don't see why auto seal key rotation shouldn't work if recovery keys haven't been generated yet"; wslabosz-reply wrote that it is "working as intended", because "while using self-initialization you *need* to generate the recovery key-shares yourself" [25]. The workarounds in the thread are making recovery keys first, or `bao write -force sys/rotate/root` after the first restart [25]. GitHub's search API lists the issue as closed, reason "completed", on 2026-09-28, but no fix for it is listed in the changelog for 2.7.0 to 2.7.2 [26] (sourced for the issue text; measured for its state, a `search/issues` call on 2026-11-14, and for the changelog, a text search of `CHANGELOG.md` on main the same day).

## Evidence for and against (REQ-0034)

| Choice | For | Against |
|---|---|---|
| Own VM | Outlives c1 teardowns and holds c1's rebuild secrets (22) | One node, one more VM to patch |
| In c1 | Three replicas, chart snapshot job | Lost with c1; can't hold what rebuilds c1 |
| Static seal | Built in, no outside service, works with self-init (8, 12) | Key on the same VM as the data; docs say evaluate carefully (8) |
| Azure Key Vault seal | Key off the VM | Plugin (9), billable, credential on the VM, needs the internet |
| vTPM seal | Key not copyable as a file | Plugin (9), TPM state must survive a VM teardown |
| ESO Vault provider | Stable (14), already the planned route (RB-0012) | OpenBao page alpha, tested on old versions (14) |
| JWT auth | No network path to the API, no stored token (16) | Revoked token valid to expiry (16); new key each rebuild (18) |
| SOPS with age | Works before OpenBao exists; two recipients (21) | Key names in clear (20); one more tool |
| No SOPS | One tool fewer | No off-machine copy of the bootstrap files (22); the box's copy is plain text (23) |
| SOPS with transit | One key system | Files unreadable while OpenBao is down, exactly when rebuilding it (19, inferred) |

## How the decision used it

Findings 1 to 4 pass REQ-0032 and the owner's "FOSS not OSS". Finding 22 and the rebuild goal set option 1. Findings 7, 8 and 12 set seal A and rule 5. Finding 10 set rule 4's copies of the key; since 2026-11-14 the box holds the only one off the VM. Findings 12 and 25 set rule 5's prod with no recovery shares, and finding 26 its open question on rotation. Finding 11 sets the seal's exit path. Finding 13 sets rule 8. Findings 14 to 18 set rule 6 and the Confirmation's ExternalSecret steps. Findings 19 to 21 set rule 10. Finding 24 sets rule 7.

## Limits

- No OpenBao or SOPS command was run for this record. The Confirmation's six dev steps are the measurement.
- External Secrets' OpenBao rating is for its own page; how its Vault provider behaves against OpenBao 2.7.2 is untested here.
- Incident reports from other OpenBao operators were not searched.
- How a VM's virtual TPM state behaves through a Proxmox teardown and restore was not researched; it matters only for seal C.

## References

Relied on (the decision depends on these):

1. OpenBao, `LICENSE` at v2.7.2. <https://github.com/openbao/openbao/blob/v2.7.2/LICENSE>, read from a clone 2026-11-14.
2. OpenBao, `CHARTER.md` at v2.7.2, sections on licences and marks. <https://github.com/openbao/openbao/blob/v2.7.2/CHARTER.md>, read from a clone 2026-11-14.
3. OpenBao, "Migration" policy and namespaces docs, in `website/content` at v2.7.2. <https://openbao.org/docs/concepts/namespaces/>, read from a clone 2026-11-14.
4. OpenBao plugins, `LICENSE`. <https://github.com/openbao/openbao-plugins/blob/main/LICENSE>, fetched 2026-11-14.
5. SOPS, `LICENSE` and `README.rst` at v3.13.3. <https://github.com/getsops/sops/tree/v3.13.3>, read from a clone 2026-11-14.
6. age, `LICENSE`. <https://github.com/FiloSottile/age/blob/main/LICENSE>, fetched 2026-11-14.
7. External Secrets, `LICENSE` at v2.14.0. <https://github.com/external-secrets/external-secrets/blob/v2.14.0/LICENSE>, fetched 2026-11-14.
8. OpenBao, "Install". <https://openbao.org/docs/install/>, read from a clone 2026-11-14.
9. OpenBao, "Seal/Unseal" and "seal stanza". <https://openbao.org/docs/concepts/seal/>, <https://openbao.org/docs/configuration/seal/>, read from a clone 2026-11-14.
10. OpenBao, "Static key seal". <https://openbao.org/docs/configuration/seal/static/>, read from a clone 2026-11-14.
11. OpenBao, the seal pages for transit, KMIP, PKCS#11 and Azure Key Vault. <https://openbao.org/docs/configuration/seal/>, read from a clone 2026-11-14.
12. OpenBao, "Seal/Unseal", sections Auto unseal, Recovery key and Seal migration. <https://openbao.org/docs/concepts/seal/>, read from a clone 2026-11-14.
13. OpenBao, "Self-Initialization". <https://openbao.org/docs/configuration/self-init/>, read from a clone 2026-11-14.
14. OpenBao, `operator raft` command and `sys/storage/raft` API. <https://openbao.org/docs/commands/operator/raft/>, <https://openbao.org/api-docs/system/storage/raft/>, read from a clone 2026-11-14.
15. External Secrets, "OpenBao", "HashiCorp Vault" and "Stability and support" at v2.14.0. <https://external-secrets.io/latest/provider/openbao/>, read from a clone 2026-11-14.
16. OpenBao, "JWT/OIDC: Kubernetes". <https://openbao.org/docs/auth/jwt/oidc-providers/kubernetes/>, read from a clone 2026-11-14.
17. OpenBao, "Kubernetes auth method". <https://openbao.org/docs/auth/kubernetes/>, read from a clone 2026-11-14.
18. SOPS docs, "HashiCorp Vault / OpenBao". <https://getsops.io/docs/usage/identities/hashicorp-vault-openbao/>, read from a clone of getsops/docs 2026-11-14.
19. SOPS docs, "Security". <https://getsops.io/docs/security/>, read from a clone 2026-11-14.
20. SOPS docs, "Key groups". <https://getsops.io/docs/usage/identities/key-groups/>, read from a clone 2026-11-14.
21. This repository, [rebuild-home-lab-from-scratch.md](../runbooks/rebuild-home-lab-from-scratch.md), "The private files on the controller".
22. This repository, [set-up-the-agent-box.md](../runbooks/set-up-the-agent-box.md).
23. This repository, [seed-secret-source.md](../runbooks/seed-secret-source.md), "How the store reads it".
24. OpenBao, "/sys/init" API, `recovery_shares`. <https://openbao.org/docs/api/system/init/>, fetched 2026-11-14.
25. OpenBao issue #3996, "Static unseal key rotation fails with declarative self-initialization when no recovery key exists". <https://github.com/openbao/openbao/issues/3996>, fetched 2026-11-14.
26. OpenBao, `CHANGELOG.md` on main. <https://github.com/openbao/openbao/blob/main/CHANGELOG.md>, fetched 2026-11-14.
