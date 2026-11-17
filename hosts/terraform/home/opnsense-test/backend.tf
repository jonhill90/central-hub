# State for this run folder only. Local file, outside the repository. On the agent box the
# opnsense-test wrapper gives the path at init:
#   tofu init -backend-config="path=<folder outside the repo>/opnsense-test.tfstate"
terraform {
  backend "local" {}
}
