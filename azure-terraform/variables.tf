# =============================================================================
# variables.tf — Input Variables for Azure Source Environment
# =============================================================================
# These variables parameterize the Azure deployment so the same code can be
# reused across different regions, subscription tiers, or demo environments.
#
# DESIGN DECISION: We use sensible defaults for a demo scenario. In production,
# you would override these via a terraform.tfvars file or CI/CD pipeline vars.
# =============================================================================

# ---------------------------------------------------------------------------
# General / Location
# ---------------------------------------------------------------------------
variable "location" {
  type        = string
  description = <<-EOT
    Azure region where all resources will be deployed.
    WHY "westeurope": Chosen to minimize latency for demos targeting European
    audiences. Also provides good proximity to T-Cloud's eu-de region for
    a realistic migration scenario.
  EOT
  default     = "westeurope"
}

variable "resource_group_name" {
  type        = string
  description = <<-EOT
    Name of the Azure Resource Group that will contain all demo resources.
    Using a single resource group makes cleanup easy — just delete the group.
  EOT
  default     = "rg-otel-migration-demo"
}

variable "environment" {
  type        = string
  description = "Environment label used for tagging (e.g., demo, staging, prod)"
  default     = "demo"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vnet_address_space" {
  type        = list(string)
  description = <<-EOT
    Address space for the Azure Virtual Network.
    WHY /16: Provides 65,536 IPs — more than enough for a demo cluster.
    This matches the T-Cloud VPC CIDR sizing for a fair comparison.
  EOT
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_prefix" {
  type        = string
  description = <<-EOT
    CIDR prefix for the AKS node subnet.
    WHY /20: Provides 4,096 IPs — enough for ~200 nodes with Azure CNI
    (which allocates ~30 IPs per node for pods).
  EOT
  default     = "10.0.0.0/20"
}

# ---------------------------------------------------------------------------
# AKS Cluster Configuration
# ---------------------------------------------------------------------------
variable "aks_cluster_name" {
  type        = string
  description = "Name of the Azure Kubernetes Service (AKS) cluster"
  default     = "aks-otel-source"
}

variable "kubernetes_version" {
  type        = string
  description = <<-EOT
    Kubernetes version for the AKS cluster.
    WHY 1.33: As of 2026 in westeurope, versions 1.30–1.32 are AKSLongTermSupport
    ONLY (requires Premium tier). Versions 1.33–1.35 carry KubernetesOfficial
    support which is available on standard/free tier subscriptions. 1.33 is
    chosen as a stable, non-bleeding-edge option in that range.
    Check current supported versions with: az aks get-versions --location westeurope
  EOT
  default     = "1.33"
}

variable "aks_node_count" {
  type        = number
  description = <<-EOT
    Number of worker nodes in the AKS default node pool.
    WHY 1: Free/trial Azure subscriptions have a 4 vCPU quota in westeurope.
    Standard_D4s_v3 = 4 vCPU, so only 1 node fits within quota. The OTel demo
    runs fine on a single node (all ~20 pods schedule to the same node).
    If you have a paid subscription with higher quota, increase to 3 and change
    vm_size to Standard_D4s_v3 for a realistic multi-node demo.
  EOT
  default     = 1
}

variable "aks_node_vm_size" {
  type        = string
  description = <<-EOT
    Azure VM size for AKS worker nodes.
    WHY Standard_D4s_v3: 4 vCPU / 16 GB RAM — provides enough resources for
    all OpenTelemetry demo microservices plus Velero and ArgoCD.
  EOT
  default     = "Standard_D4s_v3"
}

# ---------------------------------------------------------------------------
# Azure Container Registry (ACR)
# ---------------------------------------------------------------------------
variable "acr_sku" {
  type        = string
  description = <<-EOT
    SKU tier for the Azure Container Registry.
    WHY "Standard": Provides sufficient storage and throughput for the demo.
    "Premium" would add geo-replication which we don't need.
  EOT
  default     = "Standard"
}
