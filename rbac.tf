locals {
  aks_id           = azurerm_kubernetes_cluster.aks.id
  app_ns_scope     = "${azurerm_kubernetes_cluster.aks.id}/namespaces/${var.app_namespace}"
  kubelet_identity = azurerm_kubernetes_cluster.aks.kubelet_identity[0]

  sp_can_get_credentials = contains(["credentials", "deployer"], var.sp_access_stage)
  sp_is_deployer         = var.sp_access_stage == "deployer"
}

# ===========================================================================
# Flow 1: image pulls (AKS nodes -> ACR)
# The kubelet managed identity, NOT the service principal, pulls images.
# AcrPull = pull only. No push, no delete, no registry management.
# ===========================================================================
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  count = var.kubelet_acr_pull_enabled ? 1 : 0

  description                      = "AKS nodes pull images from the lab registry"
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = local.kubelet_identity.object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ===========================================================================
# Flow 2: Kubernetes API access for the service principal
# ===========================================================================

# Management plane: lets the SP call listClusterUserCredential, i.e. `az aks get-credentials`.
# This does NOT grant any Kubernetes permissions by itself.
resource "azurerm_role_assignment" "sp_cluster_user" {
  count = local.sp_can_get_credentials ? 1 : 0

  description                      = "SP may download the (Entra-authenticated) user kubeconfig"
  scope                            = local.aks_id
  role_definition_name             = "Azure Kubernetes Service Cluster User Role"
  principal_id                     = azuread_service_principal.deployer.object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Data plane, cluster scope: read most objects in every namespace (no Secrets, no nodes).
resource "azurerm_role_assignment" "sp_rbac_reader_cluster" {
  count = local.sp_is_deployer ? 1 : 0

  description                      = "SP may read workloads cluster-wide (no Secrets)"
  scope                            = local.aks_id
  role_definition_name             = "Azure Kubernetes Service RBAC Reader"
  principal_id                     = azuread_service_principal.deployer.object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Data plane, namespace scope: create/update Deployments, Services, Pods in the app namespace only.
resource "azurerm_role_assignment" "sp_rbac_writer_namespace" {
  count = local.sp_is_deployer ? 1 : 0

  description                      = "SP may deploy into the ${var.app_namespace} namespace only"
  scope                            = local.app_ns_scope
  role_definition_name             = "Azure Kubernetes Service RBAC Writer"
  principal_id                     = azuread_service_principal.deployer.object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ===========================================================================
# Your personal account (the "platform operator")
# Subscription Owner can download kubeconfig, but Owner has no Kubernetes
# dataActions, so with Azure RBAC enabled it is still Forbidden in kubectl.
# Instead of Cluster Admin, the operator gets:
#   - RBAC Reader at cluster scope
#   - a custom role that can only read/create namespaces
# ===========================================================================
resource "azurerm_role_definition" "namespace_provisioner" {
  count = var.operator_access_enabled ? 1 : 0

  name        = "AKS Namespace Provisioner (${var.student_name} IT3200)"
  scope       = azurerm_resource_group.lab.id
  description = "Create and read Kubernetes namespaces on AKS. Nothing else."

  permissions {
    actions = [
      "Microsoft.ContainerService/managedClusters/read",
    ]
    data_actions = [
      "Microsoft.ContainerService/managedClusters/namespaces/read",
      "Microsoft.ContainerService/managedClusters/namespaces/write",
    ]
  }

  assignable_scopes = [azurerm_resource_group.lab.id]
}

resource "azurerm_role_assignment" "operator_rbac_reader" {
  count = var.operator_access_enabled ? 1 : 0

  description          = "Operator may read workloads cluster-wide (no Secrets)"
  scope                = local.aks_id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = data.azuread_client_config.current.object_id
  principal_type       = "User"
}

resource "azurerm_role_assignment" "operator_namespace_provisioner" {
  count = var.operator_access_enabled ? 1 : 0

  description        = "Operator may create namespaces"
  scope              = local.aks_id
  role_definition_id = azurerm_role_definition.namespace_provisioner[0].role_definition_resource_id
  principal_id       = data.azuread_client_config.current.object_id
  principal_type     = "User"
}
