output "tenant_id" {
  description = "Microsoft Entra tenant ID."
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_id" {
  value = azurerm_kubernetes_cluster.aks.id
}

output "aks_cluster_identity_principal_id" {
  description = "Object ID of the AKS control-plane (cluster) managed identity."
  value       = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity (pulls images)."
  value       = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

output "kubelet_identity_client_id" {
  value = azurerm_kubernetes_cluster.aks.kubelet_identity[0].client_id
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_id" {
  value = azurerm_container_registry.acr.id
}

output "sp_display_name" {
  value = azuread_application.deployer.display_name
}

output "sp_client_id" {
  description = "Application (client) ID. Used as AZURE_CLIENT_ID."
  value       = azuread_application.deployer.client_id
}

output "sp_object_id" {
  description = "Service principal object ID. This is what role assignments reference."
  value       = azuread_service_principal.deployer.object_id
}

output "sp_secret_expires" {
  value = azuread_application_password.deployer.end_date
}

output "sp_client_secret" {
  description = "Lab client secret. Read with `terraform output -raw sp_client_secret` into an env var; never print or commit it."
  value       = azuread_application_password.deployer.value
  sensitive   = true
}

output "app_namespace" {
  value = var.app_namespace
}

output "access_summary" {
  description = "Which access stage is currently applied."
  value = {
    sp_access_stage          = var.sp_access_stage
    operator_access_enabled  = var.operator_access_enabled
    kubelet_acr_pull_enabled = var.kubelet_acr_pull_enabled
  }
}
