# =============================================================================
# main.tf — T-Cloud Target Environment Infrastructure
# =============================================================================
# This file provisions the complete T-Cloud (Open Telekom Cloud) "Landing Zone"
# that serves as the TARGET environment for the AKS-to-CCE migration demo.
#
# It creates:
#   1. VPC & Subnet         — Isolated network for the CCE cluster
#   2. SSH Keypair          — For secure access to CCE worker nodes
#   3. EIP for CCE API      — Public endpoint for kubectl access
#   4. CCE Cluster          — Managed Kubernetes (Cloud Container Engine)
#   5. CCE Node Pool        — Worker nodes to run the migrated workloads
#   6. NAT Gateway + EIP    — Outbound internet access for pulling images
#   7. SWR Organization     — Container registry to host migrated images
#
# ARCHITECTURE NOTE:
# CCE uses overlay_l2 networking (unlike Azure CNI which uses VNet-native IPs).
# This means pod IPs come from a separate container network CIDR managed by CCE,
# not from the VPC subnet. This is an important difference to highlight during
# the migration demo.
# =============================================================================

# ---------------------------------------------------------------------------
# 1. VPC & SUBNET
# ---------------------------------------------------------------------------
# The VPC is the T-Cloud equivalent of an Azure VNet. It provides network
# isolation for the CCE cluster and all associated resources.
#
# WHY separate from the existing tcloud-landing-zone VPC:
# This is an independent deployment specifically for the migration target,
# keeping the demo self-contained and easy to tear down.
# ---------------------------------------------------------------------------
resource "opentelekomcloud_vpc_v1" "vpc" {
  name = var.vpc_name
  cidr = var.vpc_cidr
}

resource "opentelekomcloud_vpc_subnet_v1" "kubernetes_subnet" {
  name       = "kubernetes-subnet"
  vpc_id     = opentelekomcloud_vpc_v1.vpc.id
  cidr       = var.subnet_cidr
  gateway_ip = var.subnet_gateway

  # T-Cloud's internal DNS resolvers — required for name resolution
  # within the VPC (e.g., resolving SWR endpoints, OBS endpoints)
  dns_list = ["100.125.4.25", "100.125.129.199"]
}

# ---------------------------------------------------------------------------
# 2. SSH KEYPAIR
# ---------------------------------------------------------------------------
# Generate an SSH keypair for CCE node access. We generate it in Terraform
# (rather than requiring the user to provide one) to simplify the demo setup.
#
# WHY TLS provider: The tls_private_key resource generates the key entirely
# within Terraform, avoiding external tool dependencies. The private key
# is stored in Terraform state — acceptable for a demo but not for production.
# ---------------------------------------------------------------------------
resource "tls_private_key" "cce_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "opentelekomcloud_compute_keypair_v2" "cce_node_key" {
  name       = "cce-migration-demo-key"
  public_key = tls_private_key.cce_key.public_key_openssh
}

# ---------------------------------------------------------------------------
# 3. EIP FOR CCE API SERVER
# ---------------------------------------------------------------------------
# A public Elastic IP (EIP) is assigned to the CCE cluster's API server.
# This allows kubectl access from the presenter's machine without needing
# a VPN or bastion host — essential for a smooth demo.
#
# WHY "5_bgp": This is T-Cloud's dynamic BGP-based public IP type,
# which provides the most reliable external connectivity.
# ---------------------------------------------------------------------------
resource "opentelekomcloud_vpc_eip_v1" "cce_eip" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "cce-api-bandwidth"
    size        = 8
    share_type  = "PER"       # PER = dedicated bandwidth (not shared)
    charge_mode = "traffic"   # Pay per GB of traffic (cost-effective for demo)
  }
}

# ---------------------------------------------------------------------------
# 4. CCE CLUSTER (Cloud Container Engine)
# ---------------------------------------------------------------------------
# This is the TARGET Kubernetes cluster. The OpenTelemetry demo will be
# migrated here from the Azure AKS source cluster.
#
# KEY CONFIGURATION CHOICES:
# - cluster_type = "VirtualMachine": Standard VM-based cluster (vs. BMS)
# - container_network_type = "overlay_l2": Uses VXLAN overlay networking.
#   This differs from Azure CNI but is CCE's most flexible networking mode.
#   Pod IPs are managed by CCE independently of the VPC subnet.
# - eip: Attaches the public EIP to the API server for external kubectl access
# ---------------------------------------------------------------------------
resource "opentelekomcloud_cce_cluster_v3" "cce_cluster" {
  name                   = var.cce_cluster_name
  cluster_type           = "VirtualMachine"
  flavor_id              = var.cce_cluster_flavor
  vpc_id                 = opentelekomcloud_vpc_v1.vpc.id
  subnet_id              = opentelekomcloud_vpc_subnet_v1.kubernetes_subnet.id
  container_network_type = "overlay_l2"

  # Attach the public EIP to the API server for external access
  eip = opentelekomcloud_vpc_eip_v1.cce_eip.publicip[0].ip_address
}

# ---------------------------------------------------------------------------
# 5. CCE NODE POOL
# ---------------------------------------------------------------------------
# The worker nodes that will run the migrated OpenTelemetry microservices.
#
# WHY initial_node_count = 3: Matches the Azure AKS source cluster to
# demonstrate a like-for-like migration. The OTel demo's ~15 microservices
# will be distributed across these nodes.
#
# WHY EulerOS 2.9: The recommended and well-tested OS for CCE nodes.
# It includes the necessary container runtime (containerd) and CCE agents.
# ---------------------------------------------------------------------------
resource "opentelekomcloud_cce_node_pool_v3" "cce_nodes" {
  cluster_id         = opentelekomcloud_cce_cluster_v3.cce_cluster.id
  name               = "otel-target-nodepool"
  os                 = "EulerOS 2.9"
  key_pair           = opentelekomcloud_compute_keypair_v2.cce_node_key.name
  initial_node_count = var.cce_node_count
  flavor             = var.cce_node_flavor
  availability_zone  = var.availability_zone

  # Root volume: OS disk — 40GB SSD is sufficient for EulerOS + container runtime
  root_volume {
    size       = 40
    volumetype = "SSD"
  }

  # Data volume: Used by containerd for image layers and container writable layers
  # 100GB SSD provides ample space for the OTel demo's ~15 container images
  data_volumes {
    size       = 100
    volumetype = "SSD"
  }
}

# ---------------------------------------------------------------------------
# 6. NAT GATEWAY + EIP (Outbound Internet Access)
# ---------------------------------------------------------------------------
# CCE worker nodes need outbound internet access to:
# - Pull container images from SWR or public registries
# - Download Helm charts during ArgoCD sync
# - Reach external telemetry endpoints
#
# WHY NAT Gateway (not direct EIP per node): Best practice — provides
# centralized outbound access without exposing individual nodes to the internet.
# All outbound traffic shares a single public IP via SNAT.
# ---------------------------------------------------------------------------
resource "opentelekomcloud_vpc_eip_v1" "nat_eip" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "nat-outbound-bandwidth"
    size        = var.nat_bandwidth_size
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "opentelekomcloud_nat_gateway_v2" "nat" {
  name                = "cce-nat-gateway"
  spec                = "1"   # Size 1 = Small (10,000 connections) — enough for demo
  router_id           = opentelekomcloud_vpc_v1.vpc.id
  internal_network_id = opentelekomcloud_vpc_subnet_v1.kubernetes_subnet.id
}

# SNAT rule: All traffic from the kubernetes subnet goes through the NAT GW
resource "opentelekomcloud_nat_snat_rule_v2" "snat" {
  nat_gateway_id = opentelekomcloud_nat_gateway_v2.nat.id
  network_id     = opentelekomcloud_vpc_subnet_v1.kubernetes_subnet.id
  floating_ip_id = opentelekomcloud_vpc_eip_v1.nat_eip.id
}

# ---------------------------------------------------------------------------
# 7. SWR ORGANIZATION (Software Repository for Container)
# ---------------------------------------------------------------------------
# The SWR organization is created in prereqs-terraform/ (under eu-de_demo
# project). We reference it here via a data source so outputs can still
# expose the organization name and registry endpoint.
#
# NOTE: If you prefer to keep everything in one config, you can replace
# this data source with the original resource block.
# ---------------------------------------------------------------------------
data "opentelekomcloud_swr_organization_v2" "swr_org" {
  name = var.swr_organization
}
