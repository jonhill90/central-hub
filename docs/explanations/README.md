# Explanations

Each page explains how one part of this system works, with a drawing. An explanation says what a part is and why it is built the way it is. Steps for doing a job are in [runbooks](../runbooks/README.md), and the reasons behind a choice are in [decisions](../decisions/README.md) (D-0026 rule 2).

Every page here gives its own sources: a file and line in this repository, or an upstream page. Nothing here links into the agent notebook (D-0026 rule 4).

| Page | What it explains |
|---|---|
| [What c1 is made of](what-c1-is-made-of.md) | Nodes, the control plane, pods and namespaces, drawn as c1 runs them |
| [How c1 keeps its data](how-c1-keeps-its-data.md) | The storage words (disk, StorageClass, volume, claim), what Ceph is, and why c1 doesn't use it |
| [When Argo CD takes over from Ansible](when-argo-cd-takes-over-from-ansible.md) | Which part of a build each tool does, in what order, and why the line sits where it does |
| [How the whole lab fits together](how-the-whole-lab-fits-together.md) | Every part of the lab on one drawing, and the places where one failure stops a lot |
| [How Keycloak's realms are laid out](how-keycloak-realms-are-laid-out.md) | One realm per environment's Keycloak, a client per app, and why there is no staging or management realm |
