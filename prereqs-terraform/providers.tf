# =============================================================================
# providers.tf — Pre-requisite Resources Provider Configuration
# =============================================================================
# This configuration provisions shared resources (OBS bucket, SWR organization)
# that must exist BEFORE the main CCE infrastructure is deployed.
#
# PROJECT SCOPE: All resources are created under the "eu-de_demo" project.
#
# AUTHENTICATION:
# Uses the same OS_* environment variables as the main T-Cloud config.
# The provider overrides OS_TENANT_NAME to target the "eu-de_demo" project.
#
#   export OS_AUTH_URL="https://iam.eu-de.otc.t-systems.com/v3"
#   export OS_DOMAIN_NAME="<Your_Domain_Name>"
#   export OS_USERNAME="<Your_Username>"
#   export OS_PASSWORD="<Your_Password>"
#   export OS_REGION_NAME="eu-de"
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    opentelekomcloud = {
      source  = "opentelekomcloud/opentelekomcloud"
      version = ">= 1.35.0"
    }
  }

  # ─────────────────────────────────────────────────────────────────────────
  # REMOTE BACKEND (S3-compatible OBS)
  # ─────────────────────────────────────────────────────────────────────────
  # AUTHENTICATION: The S3 backend uses AWS_ACCESS_KEY_ID and
  # AWS_SECRET_ACCESS_KEY environment variables. Set them to your OBS AK/SK:
  #   export AWS_ACCESS_KEY_ID="$OBS_ACCESS_KEY"
  #   export AWS_SECRET_ACCESS_KEY="$OBS_SECRET_KEY"
  # ─────────────────────────────────────────────────────────────────────────
  backend "s3" {
    bucket   = "otel-migration-tfstate"
    key      = "prereqs/terraform.tfstate"
    endpoint = "https://obs.eu-de.otc.t-systems.com"
    region   = "eu-de"

    # Required for non-AWS S3-compatible backends
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}

# ---------------------------------------------------------------------------
# Open Telekom Cloud Provider — scoped to "eu-de_demo" project
# ---------------------------------------------------------------------------
# WHY explicit tenant_name here: The main tcloud-terraform config may use a
# different project (e.g., "eu-de"). These pre-requisite resources (OBS, SWR)
# are intentionally placed in the "eu-de_demo" project for isolation.
# ---------------------------------------------------------------------------
provider "opentelekomcloud" {
  tenant_name = "eu-de_demo"
}
