# State for this run folder only. Local file on the operator's Mac, outside the repository
# (the owner, 2026-10-25: local state now). Give the path at init:
#   tofu init -backend-config="path=$HOME/.local/state/central-hub/home-dns.tfstate"
# The state holds every record of the zone (names and values, no secrets). If it is lost, make it
# again from the live zone: export-records.sh and imports.tf from git history (runbook "If it fails").
terraform {
  backend "local" {}
}
