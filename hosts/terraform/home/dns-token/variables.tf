# Private values have no default; set them in the git-ignored home.tfvars.

variable "zone_name" {
  description = "The public DNS zone at Cloudflare whose records ../dns manages. Private. No default."
  type        = string
}

variable "bootstrap_token_file" {
  description = "The 0600 file on the Mac that holds the bootstrap token (../../README.md, \"The bootstrap token\"). No default."
  type        = string
}

variable "token_file" {
  description = "Where the made token is written, mode 0600. Must be the same path as ../dns's token_file. No default."
  type        = string
}

variable "token_name" {
  description = "Name of the token in Cloudflare's token list."
  type        = string
  default     = "central-hub-dns-records"
}

variable "token_lifetime_days" {
  description = "Days from a token's creation to its expiry. 90, as for the cert-manager token."
  type        = number
  default     = 90

  validation {
    condition     = var.token_lifetime_days >= 7 && floor(var.token_lifetime_days) == var.token_lifetime_days
    error_message = "token_lifetime_days must be a whole number of at least 7."
  }
}

variable "token_renew_days" {
  description = "How many days before expiry the next apply replaces the token."
  type        = number
  default     = 14

  validation {
    condition     = var.token_renew_days >= 1 && var.token_renew_days < var.token_lifetime_days
    error_message = "token_renew_days must be at least 1 and less than token_lifetime_days."
  }
}
