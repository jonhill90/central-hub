# State for this run folder only. Local file on the operator's Mac, outside the repository.
# Give the path at init:
#   tofu init -backend-config="path=<folder outside the repo>/home-k8s-talos.tfstate"
terraform {
  backend "local" {}
}
