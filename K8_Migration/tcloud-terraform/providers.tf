# =============================================================================
# providers.tf — T-Cloud (Open Telekom Cloud) Terraform Provider Configuration
# =============================================================================
# This file configures the Terraform providers for the T-Cloud TARGET
# environment. We use the opentelekomcloud provider to interact with
# Open Telekom Cloud APIs for VPC, CCE, SWR, and other services.
#
# AUTHENTICATION:
# The opentelekomcloud provider authenticates via OpenStack-compatible
# environment variables. Before running Terraform, export:
#   export OS_AUTH_URL="https://iam.eu-de.otc.t-systems.com/v3"
#   export OS_DOMAIN_NAME="<Your_Domain_Name>"
#   export OS_TENANT_NAME="<Your_Project_Name>"
#   export OS_USERNAME="<Your_Username>"
#   export OS_PASSWORD="<Your_Password>"
#   export OS_REGION_NAME="eu-de"
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Open Telekom Cloud provider — manages all OTC resources
    # (VPC, CCE, SWR, NAT Gateway, EIP, etc.)
    opentelekomcloud = {
      source  = "opentelekomcloud/opentelekomcloud"
      version = ">= 1.35.0"
    }

    # TLS provider — used to generate SSH keypairs for CCE node access
    # WHY generate in Terraform: Avoids requiring the user to pre-create
    # and manage SSH keys. The private key is stored in Terraform state.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Open Telekom Cloud Provider
# ---------------------------------------------------------------------------
# Authentication is configured via environment variables (see above).
# The provider block is intentionally empty — all auth is handled by
# OS_* environment variables, which is the recommended approach for
# OpenStack-compatible clouds.
# ---------------------------------------------------------------------------
provider "opentelekomcloud" {
  # Authentication is handled via OS_* environment variables
}
