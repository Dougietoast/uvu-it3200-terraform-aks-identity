terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.14"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

# Both providers authenticate with whoever is signed in to the Azure CLI
# (`az login` with your personal account). No credentials live in this repo.
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id

  # azurerm v5 registers nothing by default. Register only what this lab uses.
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
  ]
}

provider "azuread" {}
