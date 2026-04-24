# =============================================================================
# outputs.tf — T-Cloud Target Environment Outputs
# =============================================================================
# These outputs expose critical values needed by downstream migration scripts:
#   - CCE cluster connection details (for kubectl and ArgoCD setup)
#   - SWR registry endpoint (for image sync scripts)
#   - SSH private key (for node debugging if needed)
#
# SECURITY NOTE: Outputs marked `sensitive = true` will be redacted in
# Terraform's CLI output. Use `terraform output -raw <name>` to retrieve them.
# =============================================================================

# ---------------------------------------------------------------------------
# CCE Cluster Outputs
# ---------------------------------------------------------------------------
output "cce_cluster_id" {
  description = "ID of the CCE cluster — used for API calls and resource references"
  value       = opentelekomcloud_cce_cluster_v3.cce_cluster.id
}

output "cce_cluster_name" {
  description = "Name of the CCE cluster"
  value       = opentelekomcloud_cce_cluster_v3.cce_cluster.name
}

output "cce_cluster_eip" {
  description = <<-EOT
    Public IP of the CCE cluster API server.
    Use this to configure kubectl:
      kubectl config set-cluster cce --server=https://<this-ip>:5443
  EOT
  value       = opentelekomcloud_cce_cluster_v3.cce_cluster.eip
}

# Certificate-based authentication outputs for kubectl / Helm / ArgoCD
output "certificate_clusters" {
  description = "CCE cluster CA certificate data (for kubectl config)"
  value       = opentelekomcloud_cce_cluster_v3.cce_cluster.certificate_clusters
  sensitive   = true
}

output "certificate_users" {
  description = "CCE user client certificate and key data (for kubectl config)"
  value       = opentelekomcloud_cce_cluster_v3.cce_cluster.certificate_users
  sensitive   = true
}

# ---------------------------------------------------------------------------
# SSH Key Output
# ---------------------------------------------------------------------------
output "cce_node_private_key" {
  description = <<-EOT
    SSH private key for accessing CCE worker nodes (for debugging).
    Save to a file:
      terraform output -raw cce_node_private_key > cce-node-key.pem
      chmod 600 cce-node-key.pem
  EOT
  value       = tls_private_key.cce_key.private_key_pem
  sensitive   = true
}

# ---------------------------------------------------------------------------
# SWR Outputs
# ---------------------------------------------------------------------------
output "swr_organization" {
  description = "SWR organization name — used as the image namespace in the registry"
  value       = data.opentelekomcloud_swr_organization_v2.swr_org.name
}

output "swr_login_server" {
  description = <<-EOT
    Full SWR registry endpoint for pushing/pulling images.
    Images are tagged as: <this-server>/<organization>/<image>:<tag>
    Example: swr.eu-de.otc.t-systems.com/otel-migration-demo/frontend:latest
  EOT
  value       = "swr.${var.region}.otc.t-systems.com"
}

# ---------------------------------------------------------------------------
# Networking Outputs
# ---------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the target VPC"
  value       = opentelekomcloud_vpc_v1.vpc.id
}

output "kubernetes_subnet_id" {
  description = "ID of the Kubernetes subnet within the VPC"
  value       = opentelekomcloud_vpc_subnet_v1.kubernetes_subnet.id
}

output "nat_gateway_eip" {
  description = "Public IP of the NAT Gateway (outbound traffic)"
  value       = opentelekomcloud_vpc_eip_v1.nat_eip.publicip[0].ip_address
}
