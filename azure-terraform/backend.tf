# =============================================================================
# backend.tf — Remote State Backend (S3-compatible OBS)
# =============================================================================
# Stores Terraform state in the shared OBS bucket created by prereqs-terraform.
#
# PREREQUISITE: Run prereqs-terraform first to create the tfstate bucket.
#
# AUTHENTICATION: Set these environment variables before running terraform init:
#   export AWS_ACCESS_KEY_ID="$OBS_ACCESS_KEY"
#   export AWS_SECRET_ACCESS_KEY="$OBS_SECRET_KEY"
# =============================================================================

terraform {
  backend "s3" {
    bucket   = "otel-migration-tfstate"
    key      = "azure/terraform.tfstate"
    endpoint = "https://obs.eu-de.otc.t-systems.com"
    region   = "eu-de"

    # Required for non-AWS S3-compatible backends
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
