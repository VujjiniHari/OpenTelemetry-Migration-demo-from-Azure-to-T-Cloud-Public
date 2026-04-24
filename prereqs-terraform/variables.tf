# =============================================================================
# variables.tf — Input Variables for Pre-requisite Resources
# =============================================================================

# ---------------------------------------------------------------------------
# Region
# ---------------------------------------------------------------------------
variable "region" {
  type        = string
  description = "Open Telekom Cloud region for OBS and SWR resources"
  default     = "eu-de"
}

# ---------------------------------------------------------------------------
# Terraform State Storage
# ---------------------------------------------------------------------------
variable "tfstate_bucket_name" {
  type        = string
  description = <<-EOT
    Name of the OBS bucket for storing Terraform remote state.
    WHY separate: Keeps infrastructure state isolated from application
    data (Velero backups). Different lifecycle, different access patterns.
  EOT
  default     = "otel-migration-tfstate"
}

# ---------------------------------------------------------------------------
# OBS (Object Storage Service) Configuration
# ---------------------------------------------------------------------------
variable "obs_bucket_name" {
  type        = string
  description = <<-EOT
    Name of the OBS bucket used by Velero for backup/restore.
    WHY "velero": Matches the default expected by install-velero.sh and
    the OBS_BUCKET environment variable.
  EOT
  default     = "velero-otel-migration-demo"
}

variable "obs_storage_class" {
  type        = string
  description = <<-EOT
    OBS storage class for the Velero bucket.
    Options: "STANDARD" (frequently accessed), "WARM" (infrequent), "COLD" (archive).
    WHY "STANDARD": Velero reads/writes backups actively during migration.
  EOT
  default     = "STANDARD"
}

# ---------------------------------------------------------------------------
# SWR (Software Repository for Container) Configuration
# ---------------------------------------------------------------------------
variable "swr_organization" {
  type        = string
  description = <<-EOT
    SWR organization (namespace) for migrated container images.
    Images will be tagged as:
      swr.<region>.otc.t-systems.com/<organization>/<image>:<tag>
    WHY "otel-migration-demo": Matches the SWR_ORG env var and the
    ArgoCD target manifests.
  EOT
  default     = "otel-migration-demo"
}
