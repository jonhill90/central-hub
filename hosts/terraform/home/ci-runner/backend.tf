# State for this run folder only. Local file, outside the repository (the owner, 2026-10-25: local
# state now). On the agent box the ci-runner wrapper gives the path at init:
#   tofu init -backend-config="path=<folder outside the repo>/home-ci-runner.tfstate"
terraform {
  backend "local" {}
}
