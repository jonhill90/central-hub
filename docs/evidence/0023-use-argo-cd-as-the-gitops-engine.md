---
record: D-0023
batch: RB-0009 (2026-10-13), updated by RB-0089 (2026-10-27)
researched: 2026-10-27
method: reading of the projects' own installation, release and support pages, and Microsoft Learn; release dates from the Go module proxy and Artifact Hub; the install manifests downloaded and checksummed; kustomize build and kubeconform against Kubernetes 1.37.0 schemas; a stand-in Ansible run
checks: "no independent check of RB-0089 yet; RB-0009's independent check re-fetched every fetched source (20 supported, 2 partly, none unsupported). A local test cluster could not start in the research container, so no live install was measured"
---

# Evidence for D-0023: which GitOps engine on c1

This file summarises the research behind D-0023. It adds nothing the research did not find.

## Question

Flux or Argo CD as c1's GitOps engine, installed with no git credential, and what changed since RB-0009 now that c1 runs at home on Kubernetes 1.37.1?

## Findings

1. **Both are graduated CNCF projects under Apache-2.0; Argo CD is used about 2.5 to 3 times as often** in the surveys RB-0009 read [1] (sourced).
2. **Kubernetes 1.37.** Argo CD's tested-versions table lists Kubernetes 1.33 to 1.36 for Argo CD 3.5 [2]. Flux says it supports every Kubernetes version supported upstream [3] (sourced).
3. **Versions allowed by STD-0003 on 2026-10-27:** Argo CD v3.5.5 (published 2026-10-12; v3.5.6 on 2026-10-20 is too new) and Flux v2.9.6 (2026-10-01; v2.10.0 on 2026-10-26 is too new) (measured from the Go module proxy).
4. **Install without a git credential.** Argo CD's `install.yaml` and `core-install.yaml` are applied with `kubectl`; the full manifest includes the API server and UI, the core one does not [2]. Flux's recommended bootstrap pushes its manifests to git; `flux install` or `kubectl apply` of its release manifest does not [4] (sourced).
5. **Image automation.** Flux's v2.9.6 release manifest includes the image automation and image reflector controllers and their three CRDs; Argo CD's manifests include no image updater (measured).
6. **UI and login.** Argo CD's initial admin password is generated and stored in clear text in `argocd-initial-admin-secret`; the guide says to delete it once changed. Argo CD isn't exposed outside the cluster by default, and `kubectl port-forward` reaches the API server and UI without exposing them [5] (sourced).
7. **Microsoft practice.** Microsoft documents Flux v2 and Argo CD as AKS cluster extensions; GitOps with Argo CD is generally available for AKS and in preview for Azure Arc [6]. Its AKS GitOps architecture calls them "two GitOps operators that you can use with AKS" [7] (sourced from search excerpts of the pages).
8. **Helm.** Argo CD renders Helm charts with `helm template`, so the Helm CLI doesn't see its releases; Flux keeps real Helm releases [1] (sourced).
9. **Checks of the install code.** The kustomization over Argo CD's v3.5.5 manifest builds 60 objects that validate against Kubernetes 1.37.0 schemas; a stand-in Ansible run issued only the install, diff and rollout commands and no source while the source switch was off (measured).

## How the decision used it

(Written from the record, not from the batch.)

D-0023 takes option 1. Finding 6 sets rule 6 (change and store the password, delete the initial Secret); the owner's statement of 2026-10-27 at 03:52 UTC sets the rest of rule 6, a DNS name through the Gateway instead of port-forward. Finding 2 is the first "Bad" consequence and the first revisit trigger. Findings 4 and 5 support rules 2 and 4 and Activation gate items 3, 4 and 6.

## Limits

- Argo CD 3.5.5 has not been run on Kubernetes 1.37 by this research; the first install on c1 is the test.
- Microsoft's pages were read as search excerpts, not fetched in full.
- No new practitioner survey since RB-0009.

## References

Relied on (the decision depends on these):

1. RB-0009 synthesis and ledger (Library `research/gitops-engine/`; Research repository `labs/central-hub/gitops-engine/`).
2. Argo CD, "Installation" (Tested versions). <https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/>
3. Flux, "Releases" (supported Kubernetes versions). <https://fluxcd.io/flux/releases/>
4. Flux, "Installation". <https://fluxcd.io/flux/installation/>
5. Argo CD, "Getting Started". <https://argo-cd.readthedocs.io/en/stable/getting_started/>
6. Microsoft Learn, "Tutorial: Deploy applications using GitOps with Argo CD". <https://learn.microsoft.com/azure/azure-arc/kubernetes/tutorial-use-gitops-argocd>
7. Microsoft Learn, "GitOps for Azure Kubernetes Service". <https://learn.microsoft.com/azure/architecture/example-scenario/gitops-aks/gitops-blueprint-aks>
