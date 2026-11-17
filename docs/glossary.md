# Glossary

What our words mean. This file is the one source for platform terms (D-0012 rule 8). Other copies point here.

Each word has one meaning. Status follows ISO 10241-1:

- **preferred**: use it.
- **admitted**: allowed, but a better word exists.
- **deprecated**: don't use it. The word check suggests the preferred term.

"Instead of" lists the forms the word check flags, separated by `;`. A form written `/like this/` is a pattern.

To add a word, propose one row in your own PR. The owner says yes or no. The check enforces only rows on `main` (D-0019 rule 6). The word check's files in `.github/vale/` are generated from this table by `.github/docs-check/gen_vale_terms.py`; never edit them by hand (D-0019 rule 5).

| Term | Status | Meaning | Source | Instead of |
|---|---|---|---|---|
| check | preferred | An automated test of a document that passes or fails. | GitHub's term for a result is "status check". | |
| lint, linter | preferred | A static check for errors, style and consistency, run without executing anything. | S. C. Johnson, "Lint, a C Program Checker", Bell Labs, 1978 | |
| front matter | preferred | The YAML block between the two `---` lines at the top of a Markdown file. | YAML 1.2.2; MADR | |
| schema | preferred | A JSON Schema 2020-12 file that lists the fields one kind of document must have. | JSON Schema 2020-12 | |
| gate | preferred | A check that must pass before a PR can merge. | GitHub rulesets, "Require status checks to pass" | |
| report-only check | preferred | A check whose findings are shown but never block a merge. | D-0019 | |
| false positive | preferred | A finding where the text is right and the check is wrong. | plain use | |
| verification | preferred | Confirmation, through objective evidence, that specified requirements are fulfilled. | ISO 9000:2015, via NIST SP 800-160v1r1 | |
| validation | preferred | Confirmation, through objective evidence, that the requirements for a specific intended use are fulfilled. | ISO 9000:2015, via NIST | |
| preferred, admitted, deprecated term | preferred | A glossary word's status: use it; allowed, but a better word exists; do not use it. | ISO 10241-1 | |
| resource pool | preferred | A Proxmox set of VMs, containers and storage that one permission can be granted on. Here, one per workload, named by job (STD-0001). | Proxmox VE Administration Guide, "Pools" | |
| workload | preferred | A set of resources, code and data that work together for one job, such as the firewall or a cluster. Here its pool and its Terraform folder share its name. | Azure Well-Architected Framework, "Workloads" | |
| VNet | preferred | A Proxmox SDN virtual network that belongs to a zone. Here, one per home VLAN. | Proxmox VE Administration Guide, "Software-Defined Network" | |
| API token | preferred | A credential made for one user, with its own permissions and expiry, that gives automation access to an API without the user's password; it can be revoked on its own. | Proxmox VE Administration Guide, "API Tokens" | |
| break-glass account | preferred | An account kept for emergencies only, when normal administrative accounts can't be used, never for everyday work. | Microsoft Entra, "Manage emergency access admin accounts" | |
| agent notebook | preferred | The agents' research and knowledge store, the repository jonhill90/agent-notebook, as distinct from the owner's own notebook. Named Research until 2026-11-08; older records call it the Research repo. | owner, Central Hub project, 2026-11-08 19:33 UTC | Research repo; Research repository |
| pass ledger | preferred | The file the agent box keeps for one repository and one head, with one line for each recorded pass (the reviewer's clearance, each council's pass, the owner's tap). A new head starts an empty ledger, so no pass carries over. | D-0056 | |
| sweep, merge sweep | preferred | The timer on the agent box that squash-merges a pull request when its head's pass ledger is complete and every check on the head is green. It is not GitHub's auto-merge. | D-0056 | |
| halt flag | preferred | The file whose existence stops the merge sweep from merging anything until it is cleared. | D-0056 | |
| grant | preferred | A rule in a tailnet's policy that lets a source (a user, a group or a tag) reach a destination on the ports it names. Access that no grant allows is denied. | Tailscale, "Grants" (tailscale.com/kb/1324/grants) | |
| tag | preferred | A label for a tailnet device that is not a person's, such as a server or a pod, declared in the policy's `tagOwners`. Rules name the tag, not a person. | Tailscale, "Tags" (tailscale.com/kb/1068/tags) | |
| pod | preferred | The smallest unit of computing that Kubernetes deploys and manages. | Kubernetes documentation, "Pods" (kubernetes.io/docs/concepts/workloads/pods/) | |
| sshd | preferred | The OpenSSH server program, which accepts SSH connections on a machine. | OpenBSD manual page sshd(8) (man.openbsd.org/sshd.8) | |
