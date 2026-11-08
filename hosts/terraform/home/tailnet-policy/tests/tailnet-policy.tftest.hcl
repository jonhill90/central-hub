# Offline tests for home/tailnet-policy: a plan against a mocked provider, so no tailnet or OAuth
# client is needed. Run from this folder: tofu init -backend=false && tofu test (STD-0005).

mock_provider "tailscale" {}

variables {
  vlans_file           = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
  proxmox_host_address = "192.0.2.10" # made up, as in home.tfvars.example
}

run "policy_fills_in_the_host_and_every_lab_vlan" {
  command = plan

  assert {
    condition     = strcontains(tailscale_acl.policy.acl, "\"192.0.2.10/32\": [\"tag:connector\"]")
    error_message = "The Proxmox host's /32 must be an auto-approved connector route."
  }

  assert {
    condition     = alltrue([for v in yamldecode(file(var.vlans_file)).lab_vlans : strcontains(tailscale_acl.policy.acl, "\"${v.cidr}\": [\"tag:connector\"]")])
    error_message = "Every VLAN in the shared VLAN file must be an auto-approved connector route."
  }

  assert {
    condition     = !strcontains(tailscale_acl.policy.acl, "$${")
    error_message = "No template placeholder may be left in the rendered policy."
  }
}

run "policy_never_replaces_a_policy_it_has_not_adopted" {
  command = plan

  assert {
    condition     = tailscale_acl.policy.overwrite_existing_content == false && tailscale_acl.policy.reset_acl_on_destroy == false
    error_message = "The policy must not overwrite a live policy it has not adopted, or reset it on destroy."
  }
}

run "rejects_an_address_with_a_prefix" {
  command = plan

  variables {
    proxmox_host_address = "192.0.2.10/32"
  }

  expect_failures = [var.proxmox_host_address]
}
