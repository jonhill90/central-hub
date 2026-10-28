# tflint settings for hosts/terraform/, passed with --config (no settings file in the repo root,
# D-0019 rule 4). The bundled Terraform rules, all of them: unused declarations, typed and
# documented variables, pinned provider versions, naming and the standard file layout.
plugin "terraform" {
  enabled = true
  preset  = "all"
}
