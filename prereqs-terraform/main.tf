# =============================================================================
# main.tf — Pre-requisite Resources (TF State + OBS Bucket + SWR Org)
# =============================================================================
# This config creates shared resources that must exist BEFORE the main
# infrastructure (CCE cluster) or migration scripts can run:
#
#   1. OBS Bucket (tfstate)     — Remote Terraform state for all configs
#   2. OBS Bucket ("velero")    — Backup storage for Velero (AKS → CCE bridge)
#   3. SWR Organization         — Container registry namespace for migrated images
#
# Both resources are created under the "eu-de_demo" project.
#
# BOOTSTRAP PROCESS:
#   Step 1: terraform apply              (local state — creates buckets + SWR)
#   Step 2: Uncomment backend in providers.tf
#   Step 3: terraform init -migrate-state (moves local state → OBS)
#   Then configure backends in azure-terraform/ and tcloud-terraform/
#
# RUN ORDER:
#   1. prereqs-terraform/  (this config)   ← Create OBS + SWR first
#   2. azure-terraform/                    ← Provision AKS source
#   3. tcloud-terraform/                   ← Provision CCE target
#   4. migration-scripts/                  ← Run migration
# =============================================================================

# ---------------------------------------------------------------------------
# 1. OBS BUCKET — TERRAFORM STATE (Remote Backend)
# ---------------------------------------------------------------------------
# Stores Terraform state for ALL configs (prereqs, azure, tcloud) in a
# shared OBS bucket. Each config uses a different key prefix:
#   - prereqs/terraform.tfstate
#   - azure/terraform.tfstate
#   - tcloud/terraform.tfstate
#
# WHY separate from Velero bucket: Terraform state is critical infrastructure
# metadata — mixing it with application backups risks accidental deletion
# during Velero lifecycle management.
#
# BUCKET NAME NOTE: OBS bucket names are globally unique. If the default
# is taken, override via var.tfstate_bucket_name.
# ---------------------------------------------------------------------------
resource "opentelekomcloud_obs_bucket" "tfstate" {
  bucket        = var.tfstate_bucket_name
  storage_class = "STANDARD"
  acl           = "private"

  # Versioning: CRITICAL for Terraform state — enables rollback if state
  # becomes corrupted or an apply goes wrong.
  versioning = true

  tags = {
    Project     = "otel-migration-demo"
    Purpose     = "terraform-remote-state"
    Environment = "demo"
    ManagedBy   = "terraform-prereqs"
  }
}

# ---------------------------------------------------------------------------
# 2. OBS BUCKET — VELERO BACKUPS (Object Storage Service)
# ---------------------------------------------------------------------------
# This bucket serves as the shared storage "bridge" for Velero backups.
# Both the AKS source cluster and CCE target cluster connect to this bucket:
#   - AKS (source): Velero writes backup data here
#   - CCE (target): Velero reads and restores from here
#
# WHY OBS (not Azure Blob): OBS exposes an S3-compatible API, which is
# natively supported by Velero's AWS plugin. This avoids cross-cloud
# authentication complexity — both clusters use the same AK/SK credentials.
#
# BUCKET NAME NOTE: OBS bucket names are globally unique across ALL T-Cloud
# tenants. If "velero" is taken, change the variable or use a unique suffix.
# ---------------------------------------------------------------------------
resource "opentelekomcloud_obs_bucket" "velero" {
  bucket        = var.obs_bucket_name
  storage_class = var.obs_storage_class
  acl           = "private"

  # Versioning: Enabled so Velero can track backup revisions.
  # Also provides an additional safety net against accidental deletion.
  versioning = true

  # Lifecycle rule: Auto-expire old backups after 30 days to control costs.
  # In production, adjust this based on your retention policy.
  lifecycle_rule {
    name    = "expire-old-backups"
    enabled = true
    prefix  = "backups/"

    expiration {
      days = 30
    }
  }

  tags = {
    Project     = "otel-migration-demo"
    Purpose     = "velero-backup-storage"
    Environment = "demo"
  }
}

# ---------------------------------------------------------------------------
# 3. SWR ORGANIZATION (Software Repository for Container)
# ---------------------------------------------------------------------------
# SWR is T-Cloud's container registry — the equivalent of Azure ACR.
# Creating an "organization" is like creating a namespace/project in SWR.
# All migrated container images will be pushed here with the format:
#   swr.<region>.otc.t-systems.com/<organization>/<image>:<tag>
#
# WHY create here (not in tcloud-terraform): The SWR organization must exist
# before the image sync script runs, which can happen in parallel with CCE
# provisioning. Separating it into pre-requisites allows:
#   - Image sync to start while CCE is still provisioning
#   - Clean separation of shared services vs. cluster infrastructure
# ---------------------------------------------------------------------------
resource "opentelekomcloud_swr_organization_v2" "swr_org" {
  name = var.swr_organization
}
