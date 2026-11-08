# Variables with no default are private values. They are filled from the git-ignored home.tfvars
# or as TF_VAR_<name> environment variables, and never written in this repository.

variable "vlans_file" {
  description = "Path to the place's shared VLAN file, which Ansible and home/network read too (the owner, 2026-10-26 06:08 UTC: one data file). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. No default."
  type        = string
}

variable "dns_vlan" {
  description = "Name of the VLAN in the shared VLAN file whose .1 address is the lab's DNS server (OPNsense Unbound on the mgmt gateway, STD-0002)."
  type        = string
  default     = "mgmt"
}

variable "zone" {
  description = "The lab's DNS zone, the same value as the inventory's opnsense_dns_zone. Private: the real zone stays out of this public repository (CLAUDE.md rule 4)."
  type        = string
}

variable "split_dns_names" {
  description = "Names under var.zone that tailnet devices ask the lab's DNS server for, each relative to the zone. A name covers itself and every name below it, so c1.prod covers api.c1.prod and *.apps.c1.prod. Every other name in the zone still goes to public DNS."
  type        = list(string)
  default     = ["c1.prod", "opnsense", "pve"]

  validation {
    condition     = length(var.split_dns_names) > 0 && alltrue([for n in var.split_dns_names : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", n))])
    error_message = "split_dns_names needs at least one name, each lowercase letters, digits, dots and hyphens, relative to the zone (no leading or trailing dot)."
  }
}

variable "connector_hostname" {
  description = "Tailnet hostname of the connector (CT 900), the same value as home/remote-access's connector_hostname. Private."
  type        = string
}

variable "connector_extra_routes" {
  description = "Routes the connector already advertises besides the lab VLANs, for example the Proxmox host's home LAN address as a /32. The route list here is the whole list that is turned on, so leaving one out turns it off. Private."
  type        = list(string)
}
