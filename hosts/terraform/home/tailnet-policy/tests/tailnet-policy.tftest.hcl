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
    condition     = alltrue([for v in yamldecode(file(var.vlans_file)).lab_vlans : strcontains(tailscale_acl.policy.acl, "\"${v.cidr}\": [\"tag:connector\"]") if lookup(v, "tailnet", true)])
    error_message = "Every VLAN in the shared VLAN file must be an auto-approved connector route."
  }

  assert {
    condition     = !strcontains(tailscale_acl.policy.acl, "$${")
    error_message = "No template placeholder may be left in the rendered policy."
  }
}

run "policy_leaves_out_a_vlan_marked_tailnet_false" {
  command = plan

  assert {
    condition     = alltrue([for v in yamldecode(file(var.vlans_file)).lab_vlans : !strcontains(tailscale_acl.policy.acl, "\"${v.cidr}\"") if !lookup(v, "tailnet", true)])
    error_message = "A VLAN marked tailnet: false in the VLAN file must not appear in the tailnet policy's lab ranges."
  }
}

run "agent_box_gets_ssh_from_agents_and_no_path_out" {
  command = plan

  assert {
    condition     = strcontains(tailscale_acl.policy.acl, "{\"action\": \"accept\", \"src\": [\"tag:agent\"], \"dst\": [\"tag:agent-box\"], \"users\": [\"claude\"]}")
    error_message = "Agents must reach the agent box by Tailscale SSH as user claude only."
  }

  assert {
    condition     = !strcontains(tailscale_acl.policy.acl, "\"src\": [\"tag:agent-box\"]")
    error_message = "tag:agent-box must have no grant or SSH rule of its own (no path to the Mac or the lab)."
  }
}

run "agents_are_denied_the_host_web_and_desktop_ports" {
  command = plan

  assert {
    condition     = strcontains(tailscale_acl.policy.acl, "\"deny\":   [\"192.0.2.10:8006\", \"192.0.2.10:443\", \"192.0.2.10:3389\"]")
    error_message = "The policy test must deny tag:agent the Proxmox host's ports 8006, 443 and 3389."
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

# External tailnets (declarative node sharing). All values below are made up, in the shape
# home.tfvars.example uses.

run "no_external_tailnets_renders_no_groups_or_sharing" {
  command = plan

  assert {
    condition     = !strcontains(tailscale_acl.policy.acl, "\"groups\"") && !strcontains(tailscale_acl.policy.acl, "\"externalTailnets\"")
    error_message = "With no external tailnets, the policy must have no groups or externalTailnets section, as before this setting."
  }
}

run "an_external_tailnet_gets_its_group_and_no_incoming_connections" {
  command = plan

  variables {
    external_tailnets = {
      example = {
        external_id = "T123456CNTRL"
        group       = "example-admins"
        members     = ["owner@example.com"]
      }
    }
  }

  assert {
    condition     = strcontains(tailscale_acl.policy.acl, "\"group:example-admins\": [\"owner@example.com\"]")
    error_message = "The group must be defined with its members."
  }

  assert {
    condition     = strcontains(tailscale_acl.policy.acl, "\"example\": {") && strcontains(tailscale_acl.policy.acl, "\"externalID\":                \"T123456CNTRL\"")
    error_message = "The external tailnet must be listed under its alias with its ID."
  }

  assert {
    condition     = strcontains(tailscale_acl.policy.acl, "\"allowIncomingConnections\":  false") && !strcontains(tailscale_acl.policy.acl, "\"allowIncomingConnections\":  true")
    error_message = "allowIncomingConnections must be false: an external tailnet never reaches a device in this one."
  }

  assert {
    condition     = strcontains(tailscale_acl.policy.acl, "\"allowExternalReferencesTo\": [\"group:example-admins\"]")
    error_message = "The external tailnet may reference only its own group."
  }
}

run "rejects_a_fourth_external_tailnet" {
  command = plan

  variables {
    external_tailnets = {
      a = { external_id = "T1111CNTRL", group = "a-admins", members = ["owner@example.com"] }
      b = { external_id = "T2222CNTRL", group = "b-admins", members = ["owner@example.com"] }
      c = { external_id = "T3333CNTRL", group = "c-admins", members = ["owner@example.com"] }
      d = { external_id = "T4444CNTRL", group = "d-admins", members = ["owner@example.com"] }
    }
  }

  expect_failures = [var.external_tailnets]
}

run "rejects_an_external_id_that_is_not_letters_and_digits" {
  command = plan

  variables {
    external_tailnets = {
      example = { external_id = "T123\", \"allowIncomingConnections\": true, \"x", group = "example-admins", members = ["owner@example.com"] }
    }
  }

  expect_failures = [var.external_tailnets]
}

run "rejects_a_group_with_its_prefix" {
  command = plan

  variables {
    external_tailnets = {
      example = { external_id = "T123456CNTRL", group = "group:example-admins", members = ["owner@example.com"] }
    }
  }

  expect_failures = [var.external_tailnets]
}

run "rejects_a_group_with_no_members" {
  command = plan

  variables {
    external_tailnets = {
      example = { external_id = "T123456CNTRL", group = "example-admins", members = [] }
    }
  }

  expect_failures = [var.external_tailnets]
}

run "rejects_two_entries_with_one_group" {
  command = plan

  variables {
    external_tailnets = {
      a = { external_id = "T1111CNTRL", group = "shared-admins", members = ["owner@example.com"] }
      b = { external_id = "T2222CNTRL", group = "shared-admins", members = ["owner@example.com"] }
    }
  }

  expect_failures = [var.external_tailnets]
}
