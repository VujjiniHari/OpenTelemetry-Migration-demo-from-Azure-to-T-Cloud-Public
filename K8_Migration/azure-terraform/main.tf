# =============================================================================
# main.tf — Azure Source Environment Infrastructure
# =============================================================================
# This file provisions the complete Azure "Landing Zone" that serves as the
# SOURCE environment for the AKS-to-CCE migration demo. It creates:
#
#   1. Resource Group      — Single container for all demo resources
#   2. Virtual Network     — Isolated network with an AKS-dedicated subnet
#   3. AKS Cluster         — Managed Kubernetes with Azure CNI networking
#   4. ACR Registry        — Container registry (images will be synced to SWR)
#   5. ACR ↔ AKS binding   — Grants AKS permission to pull images from ACR
#
# ARCHITECTURE NOTE:
# We intentionally use Azure CNI (not kubenet) because it assigns pod IPs
# directly from the VNet subnet. This gives us real-world complexity that
# mirrors production environments and makes the migration story more credible.
# =============================================================================

locals {
  common_tags = {
    project     = "otel-migration-demo"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ---------------------------------------------------------------------------
# 1. RESOURCE GROUP
# ---------------------------------------------------------------------------
# WHY a single resource group: Makes demo cleanup trivial — just delete the
# group and all child resources are automatically removed.
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(local.common_tags, {
    purpose = "AKS source cluster for AKS-to-CCE migration demo"
  })
}

# ---------------------------------------------------------------------------
# 2. VIRTUAL NETWORK & SUBNET
# ---------------------------------------------------------------------------
# The VNet provides network isolation. The AKS subnet is sized at /20 to
# accommodate Azure CNI's IP allocation model (each pod gets a VNet IP).
#
# WHY separate subnet: Best practice — isolates AKS node traffic and allows
# future addition of subnets for databases, bastion hosts, etc.
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "vnet-otel-demo"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space

  tags = local.common_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_prefix]
}

# ---------------------------------------------------------------------------
# 3. AZURE KUBERNETES SERVICE (AKS) CLUSTER
# ---------------------------------------------------------------------------
# This is the SOURCE Kubernetes cluster. The OpenTelemetry demo will be
# deployed here via ArgoCD, and then migrated to T-Cloud CCE.
#
# KEY CONFIGURATION CHOICES:
# - network_plugin = "azure" (CNI): Real-world networking, not simplified kubenet
# - load_balancer_sku = "standard": Required for public-facing LoadBalancer services
# - identity type = "SystemAssigned": Simplifies auth (no manual SP management)
# - default_node_pool: 3 nodes of D4s_v3 to handle the full OTel demo stack
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.aks_cluster_name

  # Pin to a specific minor version for reproducibility across demo runs
  kubernetes_version = var.kubernetes_version

  default_node_pool {
    name           = "default"
    node_count     = var.aks_node_count
    vm_size        = var.aks_node_vm_size
    vnet_subnet_id = azurerm_subnet.aks.id

    # Managed OS disk for reliability; 128GB is sufficient for demo workloads
    os_disk_type    = "Managed"
    os_disk_size_gb = 128

    # WHY max_pods = 110: Azure CNI defaults to 30 pods per node, which is not
    # enough for the OTel demo (~23 app pods + ~15 system pods = 38 total).
    # 110 is the Azure CNI maximum and fits comfortably within the /20 subnet
    # (4096 IPs available, 110 pod IPs per node is well within range).
    max_pods = 110

    # upgrade_settings omitted intentionally: this block only affects rolling
    # node upgrades (az aks upgrade), which we do not perform in this demo.
    # Omitting it avoids azurerm 3.x schema conflicts and does not impact
    # initial cluster creation or vCPU quota.
  }

  # SystemAssigned identity eliminates the need to create and manage a
  # separate Service Principal. Azure automatically creates and manages
  # the identity lifecycle.
  identity {
    type = "SystemAssigned"
  }

  # Azure CNI provides VNet-native pod networking. Each pod gets an IP
  # directly from the AKS subnet, enabling direct communication with
  # other VNet resources without NAT.
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    service_cidr      = "172.16.0.0/16"
    dns_service_ip    = "172.16.0.10"
  }

  tags = merge(local.common_tags, { role = "source-cluster" })
}

# ---------------------------------------------------------------------------
# 4. AZURE CONTAINER REGISTRY (ACR)
# ---------------------------------------------------------------------------
# ACR stores container images that will later be synced to T-Cloud SWR.
# This simulates a real-world scenario where a customer's CI/CD pipeline
# pushes images to their cloud-native registry.
#
# WHY random suffix: ACR names must be globally unique across Azure.
# The random_string ensures no collisions when multiple people run this demo.
# ---------------------------------------------------------------------------
resource "random_string" "acr_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_container_registry" "acr" {
  # ACR names must be alphanumeric (no hyphens/underscores) and globally unique
  name                = "acroteldemo${random_string.acr_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku

  # Admin account is disabled for security best practice.
  # AKS authenticates via its managed identity instead.
  admin_enabled = false

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# 5. ACR ↔ AKS ROLE ASSIGNMENT
# ---------------------------------------------------------------------------
# Grant the AKS cluster's kubelet identity the "AcrPull" role on the ACR.
# This allows AKS worker nodes to pull container images from ACR without
# needing docker login credentials or image pull secrets.
#
# WHY AcrPull (not AcrPush): Principle of least privilege — the cluster
# only needs to READ images, never push them.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"

  # The kubelet identity is the managed identity used by AKS nodes to
  # interact with Azure APIs (pull images, attach disks, etc.)
  principal_id = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
