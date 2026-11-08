# State for this run folder only. Local file on the operator's Mac, outside the repository
# (the owner, 2026-10-25: local state now; self-hosted S3 or Postgres revisited later).
# Give the path at init:
#   tofu init -backend-config="path=<folder outside the repo>/home-tailnet-policy.tfstate"
# The state holds the rendered policy, which names the Proxmox host's home LAN address.
terraform {
  backend "local" {}
}
