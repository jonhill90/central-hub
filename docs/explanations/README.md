# Explanations

Each page explains how one part of this system works, with a drawing. An explanation says what a part is and why it is built the way it is. Steps for doing a job are in [runbooks](../runbooks/README.md), and the reasons behind a choice are in [decisions](../decisions/README.md) (D-0026 rule 2).

Every page here gives its own sources: a file and line in this repository, or an upstream page. Nothing here links into the agent notebook (D-0026 rule 4).

![What runs where: the Proxmox host with the firewall, remote access, agent box, dev cluster, backup disk and the c1 cluster with its apps, plus the VPS outside](images/lab-overview.svg)

*The whole lab on one drawing. What each box rests on is under it on [How the whole lab fits together](how-the-whole-lab-fits-together.md).*

| Page | What it explains |
|---|---|
| [What c1 is made of](what-c1-is-made-of.md) | Nodes, the control plane, pods and namespaces, drawn as c1 runs them |
| [How c1 keeps its data](how-c1-keeps-its-data.md) | The storage words (disk, StorageClass, volume, claim), what Ceph is, and why c1 doesn't use it |
| [When Argo CD takes over from Ansible](when-argo-cd-takes-over-from-ansible.md) | Which part of a build each tool does, in what order, and why the line sits where it does |
| [How the whole lab fits together](how-the-whole-lab-fits-together.md) | Every part of the lab on one drawing, and the places where one failure stops a lot |
| [How Keycloak's realms are laid out](how-keycloak-realms-are-laid-out.md) | One realm per environment's Keycloak, a client per app, and why there is no staging or management realm |

## How the drawings are made

The figures in [images/](images/) are SVG files drawn by `images/build.py` from the box and cable lists inside it. To change one, edit the lists and run `python3 -I docs/explanations/images/build.py`. Each figure carries a light and a dark palette and its own opaque plate, so it reads on either page theme. Boxes use symbols drawn for this repository, not vendor logos: the logo sets we looked at are either trademark-restricted or unclear about public reuse, and a plain labelled block says the same thing. The Mermaid source stays under each figure.
