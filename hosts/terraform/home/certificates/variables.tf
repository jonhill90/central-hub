# Variables with no default are private values or place values. Private ones are filled at apply
# time and never written in this repository; set them in the git-ignored home.tfvars.

variable "zone_name" {
  description = "The public DNS zone at Cloudflare that cert-manager answers DNS-01 challenges in (the inventory's k8s_certs_zone). Private. No default."
  type        = string
}

variable "token_file" {
  description = "Where the made token is written, mode 0600, on the machine that runs tofu. Must be the same path as the Ansible inventory's k8s_certs_cloudflare_token_file. No default."
  type        = string
}

variable "token_name" {
  description = "Name of the token in Cloudflare's token list."
  type        = string
  default     = "central-hub-c1-cert-manager-dns01"
}

variable "token_lifetime_days" {
  description = "Days from a token's creation to its expiry (expires_on). 90, the same lifetime as the Proxmox token iac@pve!apply (AGENT-PICKS 19)."
  type        = number
  default     = 90

  validation {
    condition     = var.token_lifetime_days >= 7 && floor(var.token_lifetime_days) == var.token_lifetime_days
    error_message = "token_lifetime_days must be a whole number of at least 7."
  }
}

variable "token_renew_days" {
  description = "How many days before expiry the next apply replaces the token. An apply in that window (or later) makes a new token and a new expiry; an apply before it changes nothing."
  type        = number
  default     = 14

  validation {
    condition     = var.token_renew_days >= 1 && var.token_renew_days < var.token_lifetime_days && floor(var.token_renew_days) == var.token_renew_days
    error_message = "token_renew_days must be a whole number from 1 to token_lifetime_days - 1."
  }
}

variable "request_ip_in" {
  description = "Optional Cloudflare client IP condition: the CIDRs the token may be used from (the cluster's public egress address). Empty (the default) means no condition. Private if set; a changing home address would break renewals, so it is off."
  type        = list(string)
  default     = []
}
