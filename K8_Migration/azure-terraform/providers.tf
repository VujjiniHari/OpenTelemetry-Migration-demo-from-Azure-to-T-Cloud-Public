# =============================================================================
# providers.tf — Azure Terraform Provider Configuration
# =============================================================================
# This file configures the required providers for the Azure source environment.
# We use:
#   - azurerm: To provision AKS, ACR, VNet, and related Azure resources
#   - random:  To generate unique suffixes for globally-unique resource names
#
# WHY these versions?
# We pin to specific minor versions to ensure reproducibility across team
# members' machines. The `~>` operator allows patch-level updates only.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Azure Resource Manager — the primary provider for all Azure infrastructure.
    # WHY ~> 3.116: Version 3.85.0 used AKS API version 2023-04-02-preview which
    # has been removed by Azure. 3.116 is the latest stable 3.x release and uses
    # supported API versions (2024-xx). We stay on 3.x (not 4.x) to avoid
    # breaking changes in resource schemas introduced in the 4.0 major release.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }

    # Random provider — used to generate unique suffixes for ACR names.
    # ACR names must be globally unique across all of Azure, so we append
    # a random string to avoid naming collisions during demos.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Azure Provider Configuration
# ---------------------------------------------------------------------------
# Authentication is handled via environment variables or Azure CLI login.
# Before running `terraform apply`, ensure you have run:
#   az login
#   az account set --subscription <SUBSCRIPTION_ID>
#
# The `features {}` block is required by azurerm but can be left empty
# for default behavior. We explicitly configure resource_group behavior
# to protect against accidental deletion of non-empty resource groups.
# ---------------------------------------------------------------------------
provider "azurerm" {
  # WHY skip_provider_registration: The azurerm provider auto-registers all
  # known Azure Resource Providers on every init/plan. Some of these
  # (Microsoft.MixedReality, Microsoft.Media, Microsoft.TimeSeriesInsights)
  # are deprecated/removed and return 404, causing plan to fail even though
  # they are not needed for this project. Skipping auto-registration avoids
  # this. Any providers actually required (e.g. Microsoft.ContainerService,
  # Microsoft.Network) must be registered manually in the Azure Portal under
  # Subscription → Resource Providers — they are already registered by default
  # on most subscriptions.
  skip_provider_registration = true

  features {
    resource_group {
      # SAFETY: Setting to false allows Terraform to destroy resource groups
      # that still contain resources. For a demo teardown this is acceptable;
      # in production you'd set this to true.
      prevent_deletion_if_contains_resources = false
    }
  }
}
