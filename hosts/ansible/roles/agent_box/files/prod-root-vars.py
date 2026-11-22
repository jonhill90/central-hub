# /usr/local/libexec/agent-box/prod-root-vars.py: the variables that make prod's root Application (the GitOps source), in ONE
# place. rebuild-prod.sh (the rebuild's `gitops` stage) and c1-ansible.sh (`gitops`) both build the box's copy of prod's inventory,
# and both run hosts/ansible/playbooks/k8s-gitops.yml, whose source.yaml renders these as the root's Helm parameters. A name set in
# one copy and not the other makes `c1-ansible check gitops` plan to remove a parameter prod's rebuild set (openbaoAdminAddress,
# notebookRunner, localPathStableFolders: found 2026-11-22), and applying it would drop what they switch on. So both exec this file
# from `python3 -I -c`; it is not run alone. Installed by the agent_box role, root-owned.
#   settings   <work>/openbao-prod.json (agent_box_openbao_prod): seal_node, store_host, box_cidr, admin_address.
#   die(msg)   the caller's own way to stop with a message.
# The caller needs `import ipaddress, json` before it execs this file.

# The values the controller's inventory may hold and the box must not pass through (they name the Mac's files or the Mac's view of
# the store); each is set below from the box's own settings, or left unset.
ROOT_VARS_DROP = {
    "k8s_gitops_source_openbao_address", "k8s_gitops_source_openbao_ca_file", "k8s_gitops_source_openbao_measure",
    "k8s_gitops_source_openbao_in_cluster", "k8s_gitops_source_openbao_seal_node", "k8s_gitops_source_openbao_box_cidr",
    "k8s_gitops_source_openbao_store_host", "k8s_gitops_source_openbao_admin_address", "k8s_gitops_source_notebook_runner",
}


def read_root_settings(path, die):
    """The store's settings, checked. Returns (seal, store, cidr, admin)."""
    s = json.load(open(path))
    seal, store, cidr = s.get("seal_node") or "", s.get("store_host") or "", s.get("box_cidr") or ""
    if not seal or not store: die("openbao-prod.json needs seal_node and store_host")
    if cidr:
        try: n = ipaddress.ip_network(cidr, strict=False)
        except ValueError: die("box_cidr must be one address as a /32")
        if n.prefixlen != 32 or n.is_loopback: die("box_cidr must be one address as a /32")
    admin = s.get("admin_address") or ""
    if admin:
        try: a = ipaddress.ip_address(admin)
        except ValueError: a = None
        if a is None or a.version != 4 or a.is_loopback: die("admin_address must be one IPv4 address, not loopback")
        if not cidr: die("admin_address needs box_cidr: only the box's /32 may reach the admin address")
    return seal, store, cidr, admin


def set_root_vars(v, names, seal, store, cidr, admin, die):
    """Set prod's root-source variables on the k8s_nodes vars `v`. `names` is the set of k8s_nodes host names."""
    if seal not in names: die("seal_node is not a k8s_nodes host of the prod inventory")
    v["k8s_gitops_source_openbao_in_cluster"] = True
    # The notebook CI runner pod is prod's only (docs/runbooks/run-the-notebook-runner-on-c1.md).
    v["k8s_gitops_source_notebook_runner"] = True
    v["k8s_gitops_source_openbao_seal_node"] = seal
    v["k8s_gitops_source_openbao_store_host"] = store
    if cidr: v["k8s_gitops_source_openbao_box_cidr"] = cidr
    if admin: v["k8s_gitops_source_openbao_admin_address"] = admin
    # Prod's own snapshot comes back onto stable folder names, so the new claims find the restored folders.
    v["k8s_gitops_source_local_path_stable_folders"] = True
