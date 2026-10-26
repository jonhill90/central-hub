# State for this run folder only. Local file on the operator's Mac, outside the repository
# (Jon 2026-10-25: local state now; self-hosted S3 or Postgres revisited later).
# Give the path at init:
#   tofu init -backend-config="path=<folder outside the repo>/home-firewall.tfstate"
terraform {
  backend "local" {}
}
