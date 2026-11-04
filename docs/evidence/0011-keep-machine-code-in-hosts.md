---
record: D-0011
batch: RB-0086, with the naming rules from RB-0036 (evidence file 0008)
researched: 2026-10-26
method: reading of vendor and practitioner guidance on folder order (Terraform, OpenTofu, Ansible, Azure Machine Configuration, Atmos, Pulumi); repository mining of 29 public repositories at pinned commits; local Ansible runs on throwaway trees; counts of what a change of order would move; known-item recall check; independent check
checks: "an independent check re-opened a sample of 22 of 57 source rows, 9 of 29 repository rows and 7 of 12 measured rows; no sampled source was unsupported or invented, and its 12 fixes were applied. The known-item recall check found 80 of 98 known items (81.6%), with no category below 50%"
---

# Evidence for D-0011: what goes first under hosts/

This file summarises the research behind D-0011's folder order. It adds nothing that the research did not find. Each finding below traces to the batch's synthesis, its strand files or its independent check. D-0011's naming rules (a root folder is named for its job) rest on batch RB-0036, summarised in [0008-name-the-prd-specs-and-root-folders.md](0008-name-the-prd-specs-and-root-folders.md), finding 2.

## Question

When one repository holds machine code for several tools and several places, what do others put first under a folder like `hosts/`: the tool, the place, or another order? What are the sourced pros, cons and exit paths of each? The batch made no pick.

## Findings

1. **No vendor or standard sets an order across tools.** Each vendor page speaks about one tool's run folders: environment folders first (HashiCorp without HCP, Brikman, Gruntwork, Terramate, Spacelift), service first (Google, Masterpoint), or the place as data inside one project (AWS `envs/<env>/`, Ansible `inventories/<env>/` with one shared `roles/`) [1, 2, 3, 4, 5, 6, 7, 8, 9]. No standard in the sweep prescribes a repository folder order. Only Atmos speaks across tools: code by tool, configuration by place [10] (sourced).
2. **Five orders were drawn on the draft.** A tool first (`hosts/<tool>/<place>/`), B place first (`hosts/<place>/<tool>/`), C workload first (`hosts/<workload>/<tool>/`), D layer first, in run order (`hosts/1-network/`, `hosts/2-machines/`), and E mixed: shared code by tool, places by place (inferred from findings 1 and 3).
3. **Real repositories lean place first in this sample, tool first at the root in a wider one.** Of 8 eligible repositories (two or more machine tools and two or more places), 1 is tool first [11], 4 are place or system first [12, 13, 14, 15], 2 are mixed [16] and 1 is other. Counting CloudFormation as a machine tool gives 4 tool first, 4 place first and 2 mixed, of 10. The sample was searched for place-first examples on purpose. In the wider RB-0036 sample, 18 of 24 repository roots were named by tool and none by environment, which classifies roots, not the level under a `hosts/`-like folder (trees measured; classification inferred).
4. **In place-first repositories the top folder names the platform,** such as `azure/`, `proxmox/` or `vsphere/`, not a site name [12, 13, 14] (measured).
5. **Shared code is the crux.** Under place first, shared Ansible roles were copied per place [12], kept in one place that others point at [14], or put in a catalog reached by a relative path [16]. In the copied case the copies differ: the Azure copy differs from the Proxmox and ESXi copies for all 5 shared roles (measured), and part of that difference is drift (inferred). Microsoft's landing-zone guidance says never to copy code between environment folders, because it "leads to configuration drift" [17] (sourced). Under tool first, shared roles sit in the one Ansible project's `roles/`, as Ansible's own docs advise [8] (sourced).
6. **Each tool works under every order.** Ansible uses the first `ansible.cfg` it finds, and a relative `roles_path` is read from that file's folder, so a place-first project can reach a shared folder (measured with ansible-core 2.21.5 on throwaway trees). A Terraform run folder can sit at any path. An Azure Machine Configuration package imposes no repository layout [18] (sourced).
7. **In folder counts the trade is a mirror image.** Under tool first, replacing a tool used in every place changes one folder, and adding a place touches each tool folder it uses. Under place first, adding a place adds one folder, and replacing a tool touches every place that uses it. Two things are not mirrored: under place first or mixed, shared code needs a third home or copies, and each place that uses Ansible needs its own `ansible.cfg`. The files rewritten when a tool is replaced are the same under every order (inferred from the trees).
8. **A change of order now is small.** On central-hub at 6a7defe, `hosts/` paths appear 4 times, all inside D-0011, and in no CI or code-owner path (measured). The draft code had no state that a move would touch (measured on one copy of the draft).
9. **Strongest case against each.** Tool first: one place's code is spread over two or three folders (inferred), and Martin argues, about application code, that "Frameworks are tools to be used, not architectures to be conformed to" [19]; applying that to infrastructure folders is an analogy (inferred). Place first: code used in two or more places has no natural home (finding 5). Workload first: Ansible roles do not map one to one onto Terraform workloads, so roles end up in several folders (inferred). Layer first: neither layer-first repository found holds several tools and several places [20, 21] (measured).

## How the decision used it

(Written from the record, not from the batch.)

D-0011 lists orders B to E as options 4 to 7 and keeps option 1, tool first. The owner said yes to keeping it on 2026-10-26 at 04:11 UTC, after reading the five orders. Under option 1, each tool keeps one native project, so shared Ansible roles have one home (finding 5), and replacing a tool replaces one folder (finding 7). The place sits at the second level in both tools, as `hosts/terraform/<place>/` and `hosts/ansible/inventories/<place>/` (rule 7).

## Limits

- No source compares tool first and place first for a multi-tool repository directly. The comparison is built from single-tool guidance, repository mining and the draft's tree.
- The repository sample is not random. GitHub code search was not available, so place-first repositories were found by web search and over-represent place first.
- One more order, host or machine first (`hosts/<machine>/`), was not sourced.
- No mined repository holds Azure Machine Configuration packages beside Terraform, so the Azure half of every option has no repository evidence.
- Which change happens more often, replacing a tool or adding a place, is not in the sources.
- Some books and papers were read only as previews or not at all; the recall check lists them.

## References

Relied on (the decision depends on these):

1. HashiCorp, Terraform style guide, "Repository structure" and "Multiple environments". <https://developer.hashicorp.com/terraform/language/style>
2. Google Cloud, "Best practices for root modules". <https://docs.cloud.google.com/docs/terraform/best-practices/root-modules>
3. AWS Prescriptive Guidance, "Best practices for code base structure and organization". <https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/structure.html>
4. Gruntwork, terragrunt-infrastructure-live-example README, at d106b47a. <https://github.com/gruntwork-io/terragrunt-infrastructure-live-example/tree/d106b47ad1e22cae3a841cd495eae48e9bbe3a03>
5. Terramate, "Stacks". <https://terramate.io/docs/cli/stacks/>
6. Spacelift, "Infrastructure as code architecture patterns". <https://spacelift.io/blog/infrastructure-as-code-architecture-patterns>
7. Brikman, "How to manage Terraform state". <https://gruntwork.io/blog/how-to-manage-terraform-state>
8. Ansible documentation at 4b6088a4: `tips_tricks/sample_setup.rst` ("Alternative directory layout") and `playbook_guide/playbooks_reuse_roles.rst` ("Storing and finding roles"). <https://github.com/ansible/ansible-documentation>
9. Masterpoint, "The Terralith". <https://masterpoint.io/blog/terralith-monolithic-terraform-architecture/>
10. Cloud Posse Atmos, "Concepts overview", at beecbc03 (`website/docs/learn/concepts-overview.mdx`). <https://github.com/cloudposse/atmos>
11. mkuthan/homelab-public at 452782c1. <https://github.com/mkuthan/homelab-public/tree/452782c1e4dae6d674a8ade2ff289ff9a44b3543>
12. clong/DetectionLab at a4fd7271. <https://github.com/clong/DetectionLab/tree/a4fd7271271e89ea597d1513f70b3611405c0135>
13. acm-uic/IaC at 95c34691. <https://github.com/acm-uic/IaC/tree/95c34691646624b92f47b41c149bac27985ecdf9>
14. meirongdev/homelab at d539593b. <https://github.com/meirongdev/homelab/tree/d539593bb1bfff1f36fbeab3e7e33e732ebe82b6>
15. thapabishwa/home-ops at 0dc45120. <https://github.com/thapabishwa/home-ops/tree/0dc4512037fc3353c9ff7b91da630097252cec3f>
16. chezmoi-sh/atlas at 5e73be98. <https://github.com/chezmoi-sh/atlas/tree/5e73be983521790f7e8a9cf50f21afe58dbfd164>
17. Microsoft Cloud Adoption Framework, "Use infrastructure as code to update an Azure landing zone", Repository structure. <https://learn.microsoft.com/azure/cloud-adoption-framework/ready/considerations/infrastructure-as-code-updates>
18. Microsoft Learn, "How to create custom machine configuration package artifacts". <https://learn.microsoft.com/azure/governance/machine-configuration/how-to/develop-custom-package/2-create-package>

Background (read, not relied on):

- [19] Robert C. Martin, "Screaming Architecture" (2011). <https://blog.cleancoder.com/uncle-bob/2011/09/30/Screaming-Architecture.html>
- [20] khuedoan/homelab at 606a2557. <https://github.com/khuedoan/homelab/tree/606a2557fb7b20630cf4a3c817c33f4ee8048d49>
- [21] terraform-google-modules/terraform-example-foundation at 48cbcc88. <https://github.com/terraform-google-modules/terraform-example-foundation/tree/48cbcc881441e45ee6fa2af4872476560913edaa>

All read or cloned on 2026-10-26.

## Working files

The source and repository rows, the measured runs, the known-item list and recall check, the independent check and the drawing of the five orders are kept in the owner's private research archive as batch RB-0086. They are not needed to read this file.
