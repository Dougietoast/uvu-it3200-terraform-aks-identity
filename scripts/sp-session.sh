#!/usr/bin/env bash
# Load a service principal session into the CURRENT shell.
# Usage (from the repo root, in its own terminal tab):
#   source scripts/sp-session.sh
#
# - Uses a separate Azure CLI profile (~/.azure-sp) so your personal `az login`
#   in other tabs is not overwritten.
# - Uses a separate kubeconfig (~/.kube/m9-sp.kubeconfig).
# - Reads the client secret from Terraform state into an env var without printing it.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Run this with: source scripts/sp-session.sh" >&2
  exit 1
fi

export AZURE_CONFIG_DIR="$HOME/.azure-sp"
export KUBECONFIG="$HOME/.kube/m9-sp.kubeconfig"
mkdir -p "$AZURE_CONFIG_DIR" "$HOME/.kube"

export AZURE_TENANT_ID="$(terraform output -raw tenant_id)"
export AZURE_SUBSCRIPTION_ID="$(terraform output -raw subscription_id)"
export AZURE_CLIENT_ID="$(terraform output -raw sp_client_id)"
export AZURE_CLIENT_SECRET="$(terraform output -raw sp_client_secret)"
export RG="$(terraform output -raw resource_group_name)"
export AKS="$(terraform output -raw aks_name)"
export AKS_ID="$(terraform output -raw aks_id)"
export ACR_LOGIN_SERVER="$(terraform output -raw acr_login_server)"
export NS="$(terraform output -raw app_namespace)"

PS1="(m9-SP) ${PS1}"

echo "Service principal session loaded."
echo "  AZURE_CLIENT_ID = $AZURE_CLIENT_ID"
echo "  AZURE_CLIENT_SECRET = (set, hidden)"
echo "  AZURE_CONFIG_DIR = $AZURE_CONFIG_DIR"
echo "  KUBECONFIG = $KUBECONFIG"
