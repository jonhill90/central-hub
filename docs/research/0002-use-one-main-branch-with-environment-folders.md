---
record: D-0002
batch: RB-0002
researched: 2026-10-11
method: rapid review of about 30 primary sources on branching and GitOps environments; repository mining of 19 public repositories at commit SHAs and every pull request in the owner's 7 readable repositories; one independent design with a contrarian case; a gap-fill pass with citation snowballing and a search for counter-evidence
checks: 39 unique web sources (36 fetched, 2 from memory, 1 partly); 19 repositories, against a minimum of 10; the independent design kept unedited and every disagreement listed
---

# Evidence for D-0002: one main branch, environments as folders

This file summarises the research behind D-0002. It adds nothing that the research did not find. Each finding below traces to the batch's synthesis, its sources list or its repository tables.

## Question

Should central-hub use one long-lived branch or one branch per environment, and how should short-lived branches be named?

## Findings

1. **No sampled repository deploys from hand-edited environment branches.** All 19 use one trunk (`main` in 15, `master` in 4). Where environments or clusters exist, they are folders on the trunk (10 repositories), such as `clusters/<env>` or `envs/`. Single-cluster homelabs usually have no environment layer at all (7 repositories), and the two that grew past one cluster added cluster folders, not branches [19]. (Measured.)
2. **The GitOps tools document folders.** Flux's guide keeps every environment's configuration on one branch [1], and the Kustomize glossary models environments as overlays over one base [2]. Kapelonis calls environment branches an anti-pattern for configuration [3], and Thoughtworks put branch-per-environment on Hold in 2021 [4].
3. **General branching models favour one trunk.** Trunk-based development, GitHub flow, DORA and the git-flow author's 2020 note all favour one trunk for continuously delivered systems [5, 6, 7, 8]. GitLab describes branch per environment without endorsing it [9].
4. **Terraform is the exception.** For pull-based Kubernetes configuration, no primary source found recommends hand-edited environment branches. For push-based Terraform, Google Cloud does, and HashiCorp allows a branch per workspace as a fallback; AWS, Microsoft and Terragrunt use one trunk [18].
5. **Applications move by image tag.** Application code reaches environments by promoting an immutable image tag through the configuration repository, not by application branches [18].
6. **The one live case for environment branches is machine-rendered ones.** The rendered manifests pattern and Argo CD's Source Hydrator (beta) write environment branches by machine, while people edit only `main`. It can be added later on top of folders [10, 11].
7. **Switching cost.** Moving from folders to branches later is cheap; moving from hand-edited environment branches back to folders is expensive, because the branches drift apart. (Inferred from how the tools work.)
8. **Branch names.** The owner's repositories already use Conventional Commits types as branch prefixes: `fix/` 812, `feat/` 432, `docs/` 336, `chore/` 70, `test/` 38, `refactor/` 16, `ci/` 10, which is 72% of 2,379 pull requests [19]. The only versioned branch-name specification, Conventional Branch 1.1.0, accepts `feat/` and `fix/` as aliases [12]; `feat` and `fix` are Conventional Commits types, the other types come from commitlint's conventional list, and git's ref-name rules set the hard limits [13, 14, 15]. Vendor-named prefixes are rare in the owner's repositories (4 of 2,379) [19].
9. **Enforcement.** Whether the free GitHub plan can enforce a branch-name pattern is unverified, because GitHub's documentation disagrees [16, 17].

## How the decision used it

(Written from the record, not from the batch.)

D-0002 chooses one `main` branch with environments as folders because of findings 1 to 3 and 7. It notes the Terraform exception from finding 4 and keeps machine-rendered branches (finding 6) as a later option. Its branch types follow finding 8, and it only warns on branch names because of finding 9.

## Limits

- The GitHub API was blocked for third-party repositories, so their branch names come from merge commits and search, and some windows are only partly resolved.
- One of the owner's repositories could not be read.
- The branch-name search looked only for certain prefixes, so it could miss names such as `env/prod`.

## References

Relied on (the decision depends on these):

1. Flux, "Ways of structuring your repositories". <https://fluxcd.io/flux/guides/repository-structure/>
2. Kustomize glossary. <https://kubectl.docs.kubernetes.io/references/kustomize/glossary/>
3. K. Kapelonis, "Stop using branches for deploying to different GitOps environments". <https://octopus.com/blog/stop-using-branches-deploying-different-gitops-environments>
4. Thoughtworks Technology Radar, "GitOps". <https://www.thoughtworks.com/radar/techniques/gitops>
5. Trunk-based development. <https://trunkbaseddevelopment.com/>
6. GitHub flow. <https://docs.github.com/en/get-started/using-github/github-flow>
7. DORA, "Trunk-based development". <https://dora.dev/capabilities/trunk-based-development/>
8. V. Driessen, "A successful Git branching model", with the 2020 note. <https://nvie.com/posts/a-successful-git-branching-model/>
9. GitLab, "Branching strategies". <https://docs.gitlab.com/user/project/repository/branches/strategies/>
10. Akuity, "The rendered manifests pattern". <https://akuity.io/blog/the-rendered-manifests-pattern>
11. Argo CD, "Source Hydrator". <https://argo-cd.readthedocs.io/en/stable/user-guide/source-hydrator/>
12. Conventional Branch 1.1.0. <https://conventionalbranch.org/>
13. Conventional Commits 1.0.0. <https://www.conventionalcommits.org/en/v1.0.0/>
14. commitlint conventional config. <https://github.com/conventional-changelog/commitlint/blob/master/%40commitlint/config-conventional/src/index.ts>
15. git, `check-ref-format`. <https://git-scm.com/docs/git-check-ref-format>
16. GitHub, "Available rules for rulesets". <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>
17. GitHub, "Creating rulesets for a repository". <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository>

18. The gap-fill pass on Terraform environments and image-tag promotion (34 further sources), chiefly:
    - Google Cloud, "Best practices for version control" (Terraform). <https://docs.cloud.google.com/docs/terraform/best-practices/version-control>
    - Google Cloud, Terraform example foundation. <https://github.com/terraform-google-modules/terraform-example-foundation>
    - HashiCorp, Terraform workspaces. <https://developer.hashicorp.com/terraform/cli/workspaces>
    - AWS Prescriptive Guidance, Terraform code structure. <https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/structure.html>
    - Microsoft, Cloud Adoption Framework, development lifecycle. <https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/considerations/development-strategy-development-lifecycle>
    - Terragrunt, quick start. <https://docs.terragrunt.com/getting-started/quick-start/>
    - Flux, image update automation. <https://fluxcd.io/flux/guides/image-update/>
    - Argo CD Image Updater, update methods. <https://argocd-image-updater.readthedocs.io/en/stable/basics/update-methods/>
    - Kargo, core concepts. <https://docs.kargo.io/user-guide/core-concepts>
19. The repositories mined. Official examples: fluxcd/flux2-kustomize-helm-example, fluxcd/flux2-multi-tenancy, fluxcd/flux2-hub-spoke-example, argoproj/argocd-example-apps, argoproj-labs/argocd-autopilot, akuity/kargo-simple, akuity/kargo-advanced, codefresh-contrib/gitops-cert-level-2-examples. Homelabs: onedr0p/home-ops, onedr0p/cluster-template, bjw-s-labs/home-ops, buroa/k8s-gitops, joryirving/home-ops, tyriis/home-ops, billimek/k8s-gitops, khuedoan/homelab. Organisations: argoproj/argoproj-deployments, kubernetes/k8s.io, gitops-bridge-dev/gitops-bridge-argocd-control-plane-template. The owner's 7 readable repositories were counted for branch prefixes only.

Background (read, not relied on):

20. Flux example repository. <https://github.com/fluxcd/flux2-kustomize-helm-example>
21. Argo CD, "Best practices". <https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/>
22. K. Kapelonis, "How to model your GitOps environments". <https://octopus.com/blog/how-to-model-your-gitops-environments>
23. OpenGitOps principles. <https://opengitops.dev/>
24. Renovate configuration options. <https://docs.renovatebot.com/configuration-options/>

All fetched 2026-10-11.

## Working files

The practice review, the repository tables with commit SHAs, the independent design, the gap-fill pass and the reviews are kept in the owner's private research archive as batch RB-0002. They are not needed to read this file.
