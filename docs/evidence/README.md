# Evidence behind decisions

One evidence file per decision record, with the same file name as the record in [`../decisions/`](../decisions/README.md) (D-0016 rule 1). Each file summarises the research the decision rests on: the question, method, findings, checks, limits and public references. Nothing in it goes beyond what the research found.

The research batches themselves (ledgers, notes, drafts) are not here. They stay in the owner's private research archive, and each evidence file names its batch in one line.

An evidence file is frozen with its record and changes only by a correction under D-0006.

| Record | Evidence file |
|---|---|
| D-0001 | [0001-record-decisions-as-markdown-records.md](0001-record-decisions-as-markdown-records.md) |
| D-0002 | [0002-use-one-main-branch-with-environment-folders.md](0002-use-one-main-branch-with-environment-folders.md) |
| D-0003 | [0003-use-registered-id-families-and-file-qualified-labels.md](0003-use-registered-id-families-and-file-qualified-labels.md) |
| D-0005 | [0005-measure-central-hub-against-eight-pillars.md](0005-measure-central-hub-against-eight-pillars.md) |
| D-0006 | [0006-allow-corrections-to-accepted-records.md](0006-allow-corrections-to-accepted-records.md) |
| D-0007 | [0007-use-a-one-page-prd-and-frozen-per-change-specs.md](0007-use-a-one-page-prd-and-frozen-per-change-specs.md) |
| D-0008 | [0008-name-the-prd-specs-and-root-folders.md](0008-name-the-prd-specs-and-root-folders.md) |
| D-0011 | [0011-keep-machine-code-in-hosts.md](0011-keep-machine-code-in-hosts.md) |
| D-0012 | [0012-sort-docs-by-kind-of-document.md](0012-sort-docs-by-kind-of-document.md) |
| D-0014 | [0014-number-requirements-req-nnnn.md](0014-number-requirements-req-nnnn.md) |
| D-0015 | [0015-number-research-batches-rb-nnnn.md](0015-number-research-batches-rb-nnnn.md) |
| D-0016 | [0016-give-records-an-evidence-file-and-neutral-approval.md](0016-give-records-an-evidence-file-and-neutral-approval.md) |
| D-0017 | [0017-replace-kube-proxy-and-announce-lb-addresses-with-cilium.md](0017-replace-kube-proxy-and-announce-lb-addresses-with-cilium.md) |
| D-0018 | [0018-number-research-methods-rm-nnnn.md](0018-number-research-methods-rm-nnnn.md) |
| D-0019 | [0019-check-docs-on-every-pr.md](0019-check-docs-on-every-pr.md) |
| D-0020 | [0020-number-backlog-items-bl-nnnn.md](0020-number-backlog-items-bl-nnnn.md) |
| D-0021 | [0021-use-gateway-api-on-cilium-as-the-way-in-for-web-traffic.md](0021-use-gateway-api-on-cilium-as-the-way-in-for-web-traffic.md) |
| D-0022 | [0022-reach-clusters-by-ssh-now-and-keep-admin-kubeconfigs-for-break-glass.md](0022-reach-clusters-by-ssh-now-and-keep-admin-kubeconfigs-for-break-glass.md) |
| D-0023 | [0023-use-argo-cd-as-the-gitops-engine.md](0023-use-argo-cd-as-the-gitops-engine.md) |
| D-0024 | [0024-run-metrics-and-logs-on-c1-with-prometheus-grafana-and-loki.md](0024-run-metrics-and-logs-on-c1-with-prometheus-grafana-and-loki.md) |
| D-0025 | [0025-use-keycloak-behind-oidc-for-sign-in-to-lab-apps-on-c1.md](0025-use-keycloak-behind-oidc-for-sign-in-to-lab-apps-on-c1.md) |
| D-0026 | [0026-tell-documentation-from-knowledge.md](0026-tell-documentation-from-knowledge.md) |
| D-0028 | [0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md](0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md) |
| D-0030 | [0030-give-cloud-agents-one-github-account-of-their-own.md](0030-give-cloud-agents-one-github-account-of-their-own.md) |
| D-0033 | [0033-keep-c1-off-box-backups-in-azure-blob-with-restic.md](0033-keep-c1-off-box-backups-in-azure-blob-with-restic.md) |
| D-0037 | [0037-sign-in-to-proxmox-and-opnsense-through-keycloak.md](0037-sign-in-to-proxmox-and-opnsense-through-keycloak.md) |
| D-0038 | [0038-run-openbao-on-its-own-vm-as-the-secrets-store-with-sops-for-bootstrap-files.md](0038-run-openbao-on-its-own-vm-as-the-secrets-store-with-sops-for-bootstrap-files.md) |
| D-0039 | [0039-keep-lab-users-in-lldap-read-by-keycloak-and-opnsense.md](0039-keep-lab-users-in-lldap-read-by-keycloak-and-opnsense.md) |
| D-0040 | [0040-keep-opnsense-community-edition-as-the-lab-router-and-firewall-for-now.md](0040-keep-opnsense-community-edition-as-the-lab-router-and-firewall-for-now.md) |
| D-0041 | [0041-run-every-lab-and-cloud-change-through-one-logged-pipeline.md](0041-run-every-lab-and-cloud-change-through-one-logged-pipeline.md) |
| D-0042 | [0042-let-agents-approve-every-reversible-change-in-the-owners-place.md](0042-let-agents-approve-every-reversible-change-in-the-owners-place.md) |
| D-0043 | [0043-keep-tailscale-as-a-swappable-stopgap-for-reaching-the-lab.md](0043-keep-tailscale-as-a-swappable-stopgap-for-reaching-the-lab.md) |
| D-0044 | [0044-let-the-agent-box-apply-limit-changes-main-approves-by-digest.md](0044-let-the-agent-box-apply-limit-changes-main-approves-by-digest.md) |
| D-0045 | [0045-keep-the-public-zone-at-cloudflare-with-dns-01-for-certificates.md](0045-keep-the-public-zone-at-cloudflare-with-dns-01-for-certificates.md) |
| D-0047 | [0047-keep-proxmox-ve-as-the-lab-hypervisor-on-its-free-repositories.md](0047-keep-proxmox-ve-as-the-lab-hypervisor-on-its-free-repositories.md) |
| D-0048 | [0048-build-the-lab-with-opentofu-and-ansible-core.md](0048-build-the-lab-with-opentofu-and-ansible-core.md) |
| D-0050 | [0050-install-kubernetes-on-c1-with-kubeadm-from-ansible.md](0050-install-kubernetes-on-c1-with-kubeadm-from-ansible.md) |
