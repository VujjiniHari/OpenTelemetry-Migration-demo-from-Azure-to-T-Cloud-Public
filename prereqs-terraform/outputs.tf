# =============================================================================
# outputs.tf — Pre-requisite Resource Outputs
# =============================================================================
# These outputs provide the values needed by downstream scripts and configs:
#   - Terraform backend config needs the tfstate bucket name and endpoint
#   - Velero install script needs the OBS bucket name and endpoint
#   - Image sync script needs the SWR organization and registry endpoint
# =============================================================================

# ---------------------------------------------------------------------------
# Terraform State Outputs
# ---------------------------------------------------------------------------
output "tfstate_bucket_name" {
  description = "Name of the OBS bucket for Terraform remote state"
  value       = opentelekomcloud_obs_bucket.tfstate.bucket
}

output "tfstate_s3_endpoint" {
  description = <<-EOT
    S3-compatible endpoint for the Terraform state backend.
    Use this as the 'endpoint' value in backend "s3" configuration.
  EOT
  value       = "https://obs.${var.region}.otc.t-systems.com"
}

# ---------------------------------------------------------------------------
# OBS Outputs
# ---------------------------------------------------------------------------
output "obs_bucket_name" {
  description = "Name of the OBS bucket for Velero backups"
  value       = opentelekomcloud_obs_bucket.velero.bucket
}

output "obs_bucket_domain_name" {
  description = <<-EOT
    Domain name of the OBS bucket.
    Example: velero.obs.eu-de.otc.t-systems.com
  EOT
  value       = opentelekomcloud_obs_bucket.velero.bucket_domain_name
}

output "obs_bucket_region" {
  description = "Region of the OBS bucket"
  value       = var.region
}

output "obs_s3_endpoint" {
  description = <<-EOT
    S3-compatible endpoint URL for OBS.
    Used by Velero's AWS plugin as the --s3Url parameter.
  EOT
  value       = "https://obs.${var.region}.otc.t-systems.com"
}

# ---------------------------------------------------------------------------
# SWR Outputs
# ---------------------------------------------------------------------------
output "swr_organization" {
  description = "SWR organization name — used as the image namespace"
  value       = opentelekomcloud_swr_organization_v2.swr_org.name
}

output "swr_login_server" {
  description = <<-EOT
    Full SWR registry endpoint for Docker login and image push/pull.
    Example: swr.eu-de.otc.t-systems.com
  EOT
  value       = "swr.${var.region}.otc.t-systems.com"
}

output "swr_image_prefix" {
  description = <<-EOT
    Full image prefix for tagging migrated images.
    Example: swr.eu-de.otc.t-systems.com/otel-migration-demo
    Usage:   docker tag <image> <this-prefix>/<image>:<tag>
  EOT
  value       = "swr.${var.region}.otc.t-systems.com/${opentelekomcloud_swr_organization_v2.swr_org.name}"
}
