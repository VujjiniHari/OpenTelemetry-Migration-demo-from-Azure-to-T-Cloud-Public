# =============================================================================
# variables.tf — Input Variables for T-Cloud Target Environment
# =============================================================================
# These variables parameterize the T-Cloud deployment. The defaults match the
# Azure source environment where possible (e.g., similar CIDR ranges, node
# counts) to make the migration comparison straightforward.
# =============================================================================

# ---------------------------------------------------------------------------
# Region
# ---------------------------------------------------------------------------
variable "region" {
  type        = string
  description = <<-EOT
    Open Telekom Cloud region.
    WHY "eu-de": This is the primary European region for T-Cloud (Frankfurt).
    Chosen to match the Azure westeurope source for geographic proximity.
  EOT
  default     = "eu-de"
}

variable "availability_zone" {
  type        = string
  description = <<-EOT
    Availability zone within the region for CCE nodes.
    WHY "eu-de-01": The first AZ in eu-de. For a demo, a single AZ is
    sufficient. In production, you'd distribute across AZs.
  EOT
  default     = "eu-de-01"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_name" {
  type        = string
  description = "Name of the VPC (Virtual Private Cloud) for the target environment"
  default     = "vpc-otel-target"
}

variable "vpc_cidr" {
  type        = string
  description = <<-EOT
    CIDR block for the target VPC.
    WHY 10.20.0.0/16: Uses a different range from the Azure VNet (10.0.0.0/16)
    to avoid confusion, but same size (/16) for a fair comparison.
  EOT
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = <<-EOT
    CIDR block for the Kubernetes subnet within the VPC.
    WHY /18: Provides 16,384 IPs — generous for CCE nodes and pods.
    CCE uses overlay networking (overlay_l2), so pod IPs come from the
    container network CIDR, not this subnet. This subnet is for node IPs.
  EOT
  default     = "10.20.0.0/18"
}

variable "subnet_gateway" {
  type        = string
  description = "Gateway IP for the Kubernetes subnet (first usable IP)"
  default     = "10.20.0.1"
}

# ---------------------------------------------------------------------------
# CCE Cluster Configuration
# ---------------------------------------------------------------------------
variable "cce_cluster_name" {
  type        = string
  description = "Name of the Cloud Container Engine (CCE) cluster"
  default     = "cce-otel-target"
}

variable "cce_cluster_flavor" {
  type        = string
  description = <<-EOT
    CCE cluster flavor (control plane size).
    WHY "cce.s1.small": Supports up to 50 nodes, which is plenty for a demo.
    Options: cce.s1.small (50 nodes), cce.s1.medium (200), cce.s1.large (1000)
  EOT
  default     = "cce.s1.small"
}

variable "cce_node_flavor" {
  type        = string
  description = <<-EOT
    Flavor (VM size) for CCE worker nodes.
    WHY "s3.xlarge.4": 4 vCPU / 16 GB RAM — matches Azure's Standard_D4s_v3
    (4 vCPU / 16 GB) used on the source cluster. The OpenTelemetry Astronomy
    Shop runs ~20 microservices; 4 GB nodes (s3.large.2) will trigger OOMKills
    under the restored workload. Use s3.xlarge.4 for a stable demo.
    For cost savings: s3.xlarge.2 (4 vCPU / 8 GB) works with 3 nodes if you
    accept slightly reduced headroom.
  EOT
  default     = "s3.xlarge.4"
}

variable "cce_node_count" {
  type        = number
  description = <<-EOT
    Number of worker nodes in the CCE node pool.
    WHY 3: Matches the Azure source cluster for a fair comparison.
    The OpenTelemetry demo distributes ~15 microservices across these nodes.
  EOT
  default     = 3
}

# ---------------------------------------------------------------------------
# SWR (Software Repository for Container) Configuration
# ---------------------------------------------------------------------------
variable "swr_organization" {
  type        = string
  description = <<-EOT
    SWR organization name. This acts as the namespace/prefix for all images
    in the T-Cloud container registry.
    Example: Images will be tagged as swr.eu-de.otc.t-systems.com/<org>/image:tag
  EOT
  default     = "otel-migration-demo"
}

# ---------------------------------------------------------------------------
# NAT Gateway
# ---------------------------------------------------------------------------
variable "nat_bandwidth_size" {
  type        = number
  description = <<-EOT
    Bandwidth in Mbps for the NAT Gateway's EIP.
    WHY 10: Sufficient for pulling container images from the internet (SWR,
    public registries). The OTel demo images total ~5GB.
  EOT
  default     = 10
}
