---
record: D-0028
batch: "RB-0171 (lab PKI that survives rebuilds, a top-up to RB-0078)"
researched: 2026-11-08
method: a reading of the owner's own earlier lab and work notes on PKI (19 notes, read in full), research batch RB-0078, and the current vendor documentation for cert-manager, Smallstep step-ca, Proxmox VE and the OPNsense acme-client plugin
checks: no independent check yet
---

# Evidence for D-0028: the lab's own certificate authority

This file summarises what the record rests on, and it adds nothing beyond that.

## Question

Which private CA shape keeps one root across rebuilds of c1, issues certificates for Proxmox, OPNsense and the apps on c1, and can be rebuilt from this repository?

## Findings

1. **An earlier home lab lost its root on each rebuild.** Both CA keys lived only in cert-manager Secrets, and the move to the second version of that lab meant deleting the old root from every device and trusting a new one (sourced, the owner's notes).
2. **A pattern the owner used on an earlier cluster survived losing it.** A root outside the cluster signed one platform intermediate (path length 0), kept with its key in a key vault and copied into a Secret at deploy. Losing the cluster meant restoring the Secret and recreating the issuer (sourced, the owner's notes).
3. **One intermediate per cluster** is better than one shared by all clusters (sourced, the owner's notes; the same finding as an earlier review of the lab plan).
4. **cert-manager's CA issuer** is described upstream as for demos or for users with tooling for running a PKI; it doesn't rotate the CA Secret; for an intermediate, `tls.crt` must hold the full chain (sourced, <https://cert-manager.io/docs/configuration/ca/>).
5. **The CA issuer has no ACME server**, so nothing outside Kubernetes can order certificates from it (model).
6. **step-ca** can serve ACME to cert-manager, Proxmox and OPNsense, and defaults to 24-hour certificates; it keeps ACME accounts in its own database (sourced, <https://smallstep.com/docs/tutorials/kubernetes-acme-ca/>, <https://smallstep.com/docs/step-ca/configuration>).
7. **Proxmox VE** accepts a custom ACME directory once the host trusts the private root, and the **OPNsense acme-client** plugin supports custom ACME CAs from version 3.3 (sourced, the Proxmox forum thread 99102; the plugin's package description).
8. **cert-manager v1.21** supports Kubernetes 1.33 to 1.36; no release lists 1.37 (sourced, <https://cert-manager.io/docs/releases/>).
9. **A swap is a new intermediate under the same root**, so devices keep their trust (sourced, RB-0078).

## How the decision used it

Findings 1 to 3 give rules 1 to 3: the root stays off the cluster, each cluster gets its own intermediate, and a rebuild restores rather than re-creates. Findings 5 to 7 are why option 2 needs a CA server and option 1 pushes certificates to Proxmox and OPNsense instead; the owner chose not to run the server. Findings 4 and 8 are the record's "Bad" consequences. Finding 9 is the exit path in rule 8.
