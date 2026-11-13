# State for this run folder only. Local file, outside the repository (the owner, 2026-10-25: local
# state now). On the agent box the desktop wrapper gives the path at init:
#   tofu init -backend-config="path=<folder outside the repo>/home-desktop.tfstate"
terraform {
  backend "local" {}
}
