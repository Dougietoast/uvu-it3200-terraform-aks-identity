data "azurerm_client_config" "current" {}

locals {
  suffix = "uvu-it3200-${var.student_name}"

  rg_name  = "rg-${local.suffix}"
  aks_name = "aks-${local.suffix}"
  acr_name = "acruvuit3200${var.student_name}${var.acr_name_suffix}" # alphanumeric only, globally unique
  sp_name  = "sp-${local.suffix}"

  tags = merge({
    course     = "IT3200"
    assignment = "M9-aks-acr-identity"
    student    = var.student_name
    managed_by = "terraform"
  }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = local.rg_name
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Azure Container Registry
#   - admin user disabled: no shared username/password, Entra ID auth only
#   - Basic SKU: anonymous pull is not available on Basic, so every pull is authenticated
#   - LegacyRegistryPermissions: standard Azure RBAC (AcrPull/AcrPush), not ABAC repo permissions
# ---------------------------------------------------------------------------
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku                 = "Basic"
  admin_enabled       = false

  role_assignment_mode = "LegacyRegistryPermissions"

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Azure Kubernetes Service
#   - SystemAssigned managed identity for the control plane (cluster identity)
#   - AKS creates a separate kubelet managed identity for the nodes
#   - Microsoft Entra ID integration with Azure RBAC for Kubernetes authorization
#   - local accounts disabled: no static cluster-admin certificate, so every
#     kubectl call must come from an Entra identity that Azure RBAC authorizes
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.aks_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = local.aks_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  local_account_disabled            = true
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                        = "system"
    node_count                  = var.node_count
    vm_size                     = var.node_vm_size
    os_disk_size_gb             = 32
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
  }

  tags = local.tags
}
