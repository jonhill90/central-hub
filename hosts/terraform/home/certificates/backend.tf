# State for this run folder only. Local file on the operator's Mac, outside the repository
# (the owner, 2026-10-25: local state now; self-hosted S3 or Postgres revisited later).
# Give the path at init:
#   tofu init -backend-config="path=<folder outside the repo>/home-certificates.tfstate"
# This state holds the made token's value in plain text (state encryption is not set up yet):
# keep the state file 0600, like the token file itself.
terraform {
  backend "local" {}
}
