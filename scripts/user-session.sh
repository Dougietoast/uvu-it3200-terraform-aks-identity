#!/usr/bin/env bash
# Load a personal-account session into the CURRENT shell.
# Usage (from the repo root):
#   source scripts/user-session.sh
#
# Uses your normal Azure CLI profile (~/.azure, signed in with `az login`)
# and a separate kubeconfig (~/.kube/m9-user.kubeconfig).

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Run this with: source scripts/user-session.sh" >&2
  exit 1
fi

unset AZURE_CONFIG_DIR AZURE_CLIENT_ID AZURE_CLIENT_SECRET AAD_SERVICE_PRINCIPAL_CLIENT_ID AAD_SERVICE_PRINCIPAL_CLIENT_SECRET
export KUBECONFIG="$HOME/.kube/m9-user.kubeconfig"
mkdir -p "$HOME/.kube"

export RG="$(terraform output -raw resource_group_name)"
export AKS="$(terraform output -raw aks_name)"
export ACR_LOGIN_SERVER="$(terraform output -raw acr_login_server)"
export NS="$(terraform output -raw app_namespace)"

PS1="(m9-USER) ${PS1}"

echo "Personal account session loaded."
echo "  Signed in as: $(az account show --query user.name -o tsv 2>/dev/null || echo 'not signed in - run az login')"
echo "  KUBECONFIG = $KUBECONFIG"
