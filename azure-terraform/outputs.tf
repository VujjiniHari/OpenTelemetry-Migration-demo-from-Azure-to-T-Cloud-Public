# =============================================================================
# outputs.tf — Azure Source Environment Outputs
# =============================================================================
# These outputs expose critical values needed by downstream scripts:
#   - AKS cluster credentials (for kubectl and ArgoCD setup)
#   - ACR login server (for image sync scripts)
#   - Resource identifiers (for migration verification)
#
# SECURITY NOTE: Outputs marked `sensitive = true` will be redacted in
# Terraform's CLI output. Use `terraform output -raw <name>` to retrieve them.
# =============================================================================

# ---------------------------------------------------------------------------
# AKS Cluster Outputs
# ---------------------------------------------------------------------------
output "aks_cluster_name" {
  description = "Name of the AKS cluster — used in `az aks get-credentials`"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_id" {
  description = "Full Azure resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "aks_resource_group" {
  description = "Resource group containing the AKS cluster"
  value       = azurerm_resource_group.main.name
}

output "aks_kube_config_raw" {
  description = <<-EOT
    Raw kubeconfig YAML for the AKS cluster.
    Use this to configure kubectl:
      terraform output -raw aks_kube_config_raw > ~/.kube/aks-config
      export KUBECONFIG=~/.kube/aks-config
  EOT
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "aks_host" {
  description = "Kubernetes API server endpoint for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].host
  sensitive   = true
}

# ---------------------------------------------------------------------------
# ACR Outputs
# ---------------------------------------------------------------------------
output "acr_login_server" {
  description = <<-EOT
    FQDN of the Azure Container Registry login server.
    Used by the image sync script to pull images before re-tagging for SWR.
    Example value: acroteldemoabc123.azurecr.io
  EOT
  value       = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  description = "Name of the ACR instance — used in `az acr login`"
  value       = azurerm_container_registry.acr.name
}

output "acr_id" {
  description = "Full Azure resource ID of the ACR"
  value       = azurerm_container_registry.acr.id
}

# ---------------------------------------------------------------------------
# Networking Outputs
# ---------------------------------------------------------------------------
output "vnet_id" {
  description = "Azure resource ID of the demo Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "aks_subnet_id" {
  description = "Azure resource ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

# ---------------------------------------------------------------------------
# Convenience: Quick-start command
# ---------------------------------------------------------------------------
output "connect_command" {
  description = "Run this command to configure kubectl for the AKS cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}
