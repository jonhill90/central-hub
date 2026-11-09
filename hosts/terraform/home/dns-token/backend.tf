# State for this run folder only. Local file on the operator's Mac, outside the repository
# (the owner, 2026-10-25: local state now). Give the path at init:
#   tofu init -backend-config="path=$HOME/.local/state/central-hub/home-dns-token.tfstate"
# This state holds the made token's value in plain text (state encryption is not set up yet):
# keep the state file 0600, like the token file itself.
terraform {
  backend "local" {}
}
