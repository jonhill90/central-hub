# Variables with no default are private values. They are filled from the git-ignored home.tfvars
# or as TF_VAR_<name> environment variables, and never written in this repository.

variable "vlans_file" {
  description = "Path to the place's shared VLAN file, which Ansible, home/network and home/tailnet read too (the owner, 2026-10-26 06:08 UTC: one data file). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. No default."
  type        = string
}

variable "proxmox_host_address" {
  description = "The Proxmox host's home LAN address, which the connector advertises as a /32 (home/tailnet's connector_extra_routes). Private: it stays out of this public repository (CLAUDE.md rule 4). No default (STD-0004 rule 2)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.proxmox_host_address)) && can(cidrhost("${var.proxmox_host_address}/32", 0))
    error_message = "proxmox_host_address must be one IPv4 address, with no prefix length."
  }
}

variable "external_tailnets" {
  description = <<-EOT
    Other tailnets that may share their own devices into this one (Tailscale's declarative node
    sharing, alpha). Keyed by a local alias, which the other tailnet does not see. Each entry names
    the other tailnet's ID, one group of this tailnet that the other tailnet may grant access to,
    and that group's members (login names). The other tailnet never reaches a device here: the
    template writes allowIncomingConnections false itself, so no value can change it. Private: the
    alias, the ID, the group and the logins stay in the git-ignored home.tfvars (CLAUDE.md rule 4).
    Default: none, which renders the policy exactly as it is without this setting.
  EOT
  type = map(object({
    external_id = string
    group       = string
    members     = list(string)
  }))
  default = {}

  validation {
    condition     = length(var.external_tailnets) <= 3
    error_message = "external_tailnets takes at most three entries, Tailscale's limit for declarative node sharing."
  }

  validation {
    condition     = alltrue([for k in keys(var.external_tailnets) : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$", k))])
    error_message = "Each external_tailnets alias must be letters, digits, '-' or '_', starting with a letter or digit, at most 63 characters."
  }

  validation {
    condition     = alltrue([for t in values(var.external_tailnets) : can(regex("^[A-Za-z0-9]{4,64}$", t.external_id))])
    error_message = "Each external_id must be the other tailnet's ID: letters and digits only, as shown under Unique IDs on its admin console's General page."
  }

  validation {
    condition     = alltrue([for t in values(var.external_tailnets) : can(regex("^[a-z0-9][a-z0-9-]{0,62}$", t.group))])
    error_message = "Each group must be a bare group name (lowercase letters, digits and '-'), without the 'group:' prefix."
  }

  validation {
    condition     = length(distinct([for t in values(var.external_tailnets) : t.group])) == length(var.external_tailnets)
    error_message = "Each external_tailnets entry needs its own group, so no group is defined twice."
  }

  validation {
    condition     = alltrue([for t in values(var.external_tailnets) : length(t.members) > 0 && alltrue([for m in t.members : can(regex("^[^\\s\"\\\\]+@[^\\s\"\\\\]+$", m))])])
    error_message = "Each group needs at least one member, and each member is one login name such as name@example.com."
  }
}

variable "share_pod_enabled" {
  description = <<-EOT
    Whether the policy holds the share pod (apps/share-pod on c1): tag:share-pod in each external
    tailnet's allowExternalReferencesTo, its tagOwners line, the agent box's grant to it on tcp 2222,
    and its two policy tests. It takes effect only with at least one external_tailnets entry. Off,
    groups and externalTailnets still render from external_tailnets, with only the group in the
    references, so a live share with no share pod is kept as it is. Turning it on is its own
    tailnet apply (D-0036 rule 8). Default: false.
  EOT
  type        = bool
  default     = false
}
