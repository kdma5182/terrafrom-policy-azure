terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.resource_group_name}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_data_collection_endpoint" "main" {
  name                = "${var.resource_group_name}-dce"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_monitor_data_collection_rule" "main" {
  name                      = var.dcr_name
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.main.id
  kind                      = "Windows"

  destinations {
    log_analytics {
      name                = "lawDest"
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf"]
    destinations = ["lawDest"]
  }

  data_sources {
    performance_counter {
      name                          = "perfCounters"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["\\Processor(_Total)\\% Processor Time"]
    }
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_log_analytics_workspace.main
  ]
}

# Assign policy to associate DCR with Windows VMs
resource "azurerm_subscription_policy_assignment" "associate_dcr_windows_vms" {
  name                 = var.policy_definition_name
  policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/9575b8b7-78ab-4281-b53b-d3c1ace2260b"
  display_name         = var.policy_display_name
  subscription_id      = var.subscription_id_full
  location             = var.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    "DcrResourceId" = {
      "value" = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Insights/dataCollectionRules/${var.dcr_name}"
    },
    "scopeToSupportedImages" = {
      "value" = false
    }
  })
}

# Grant the policy assignment's managed identity "Virtual Machine Contributor" role
resource "azurerm_role_assignment" "policy_identity_vm_contributor" {
  # Assign at the subscription scope if VMs can be in different resource groups,
  # or scope it down to specific resource groups if you prefer.
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_subscription_policy_assignment.associate_dcr_windows_vms.identity[0].principal_id
  # Explicit dependency to ensure the policy identity is created before role assignment
  depends_on = [azurerm_subscription_policy_assignment.associate_dcr_windows_vms]
}

# Grant the policy assignment's managed identity "Monitoring Contributor" role
resource "azurerm_role_assignment" "policy_identity_monitoring_contributor" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_subscription_policy_assignment.associate_dcr_windows_vms.identity[0].principal_id
  # Explicit dependency to ensure the policy identity is created before role assignment
  depends_on           = [azurerm_subscription_policy_assignment.associate_dcr_windows_vms]
}

resource "azurerm_subscription_policy_remediation" "remediate_dcr_policy" {
  name                    = "remediate-dcr-policy"
  subscription_id         = var.subscription_id_full
  policy_assignment_id    = azurerm_subscription_policy_assignment.associate_dcr_windows_vms.id
  resource_discovery_mode = "ExistingNonCompliant"
}
