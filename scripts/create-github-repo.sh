#!/usr/bin/env bash
# Creates the GitHub repo for this project and pushes the current commit.
set -euo pipefail

OWNER="Dougietoast"
REPO="uvu-it3200-terraform-aks-identity"
cd "$(dirname "$0")/.."

# 1. GitHub CLI
if ! command -v gh >/dev/null; then
  echo "Installing GitHub CLI..."
  sudo apt-get update -qq && sudo apt-get install -y gh
fi

# 2. Sign in (one-time browser code, uses your existing SSH key for git)
if ! gh auth status >/dev/null 2>&1; then
  gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key
fi

# 3. Create the repo if it doesn't exist yet
if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  echo "Repo $OWNER/$REPO already exists."
else
  gh repo create "$OWNER/$REPO" --public \
    --description "IT 3200 M9: AKS, ACR, Entra service principal and RBAC with Terraform"
fi

# 4. Make sure there is a commit, never including secrets
if git ls-files | grep -E '\.tfstate|(^|/)terraform\.tfvars$|kubeconfig'; then
  echo "STOP: a sensitive file is tracked. Fix before pushing." >&2
  exit 1
fi
git add .
git diff --cached --quiet || git commit -m "M9: AKS, ACR, service principal and RBAC with Terraform"

# 5. Remote + push
git remote get-url origin >/dev/null 2>&1 \
  || git remote add origin "git@github.com:$OWNER/$REPO.git"
git push -u origin main

echo
echo "Done: https://github.com/$OWNER/$REPO"
