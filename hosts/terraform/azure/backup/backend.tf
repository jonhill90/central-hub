# State for this run folder only. Local file on the operator's Mac, outside the repository
# (the owner, 2026-10-25: local state now; self-hosted S3 or Postgres revisited later).
# Give the path at init:
#   tofu init -backend-config="path=$HOME/.local/state/central-hub/azure-backup.tfstate"
# No secret lands in this state: shared key access is off, so the provider never reads the
# account's keys, and nothing here makes a SAS.
terraform {
  backend "local" {}
}
