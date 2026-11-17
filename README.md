# uvu-it3200-terraform-aks-identity

IT 3200 (Cloud Computing, UVU, Fall 2026) — M9 lab: **Kubernetes, Container Registry & Identity Management**.

Terraform builds an Entra-integrated AKS cluster, a private Azure Container Registry, a Microsoft Entra service principal, and every role assignment between them. A small nginx web page is pushed to ACR and deployed into AKS by the service principal, which can only write to one namespace.

| Component | Name | Purpose |
|---|---|---|
| Resource group | `rg-uvu-it3200-douglas` | Holds the lab resources |
| AKS cluster | `aks-uvu-it3200-douglas` | 1-node cluster, Entra ID auth, **Azure RBAC for Kubernetes authorization**, local accounts disabled |
| Container registry | `acruvuit3200douglas` | Basic SKU, admin user disabled, Entra auth only |
| App registration + service principal | `sp-uvu-it3200-douglas` | Deployment identity, short-lived client secret |
| Cluster managed identity | system-assigned | AKS control plane manages Azure resources (LB, disks, NICs) |
| Kubelet managed identity | created by AKS | Nodes pull images from ACR (`AcrPull`) |
| Kubernetes namespace / Deployment / Service | `hello-web` | Test app, ClusterIP only, reached with `kubectl port-forward` |

See [docs/architecture.md](docs/architecture.md) for the diagram and [docs/identities-and-permissions.md](docs/identities-and-permissions.md) for every identity and role and why it is there.

## Repository layout

```
providers.tf             AzureRM (v5) + AzureAD (v3) + time providers
variables.tf             names, region, VM size, and the access-stage toggles
main.tf                  resource group, ACR, AKS
identity.tf              Entra app registration, service principal, client secret
rbac.tf                  all Azure role assignments (+ one custom role)
outputs.tf               non-sensitive IDs (+ the secret, marked sensitive)
terraform.tfvars.example copy to terraform.tfvars (gitignored)
app/                     Dockerfile + index.html for the test image
k8s/                     namespace, deployment, service, bonus pull-test pod
scripts/                 sp-session.sh / user-session.sh to keep the two identities separate
docs/                    architecture, identities, troubleshooting, test results
```

## Prerequisites

All commands run in bash (WSL Ubuntu). Required tools: Terraform ≥ 1.9, Azure CLI, Docker, kubectl, kubelogin, envsubst, git.

```bash
# kubectl + kubelogin (installs both to /usr/local/bin)
sudo az aks install-cli
# envsubst (usually already present)
sudo apt-get install -y gettext-base

terraform version && az version -o table && kubectl version --client && kubelogin --version && docker version --format '{{.Server.Version}}'
```

You need an Azure subscription where you can create AKS/ACR, **register Entra applications**, and **create role assignments** (Owner on the subscription and permission to register apps in the tenant).

> Cost: a 1-node AKS cluster on the Free tier plus a Basic registry is on the order of 10–20 cents an hour while running (node VM, load balancer + public IP, disk, registry). Check the Azure pricing calculator for your region, do the lab in one sitting, and run `terraform destroy` at the end.

---

## Walkthrough

The access variables in `terraform.tfvars` let you move through the assignment in stages. Every permission change is a Terraform change.

| Stage | `sp_access_stage` | `operator_access_enabled` | What you prove |
|---|---|---|---|
| A | `none` | `false` | SP authenticates, but has no authorization at all |
| B | `credentials` | `false` | SP can download kubeconfig, every kubectl call is Forbidden |
| C | `credentials` | `true` | Your Owner account is *also* Forbidden until given Kubernetes roles: the cause is authorization, not a broken SP |
| D | `deployer` | `true` | SP reads the cluster and deploys into `hello-web` only |

Use **two terminal tabs**: one for your personal account (runs Terraform), one for the service principal. The session scripts keep their Azure CLI profiles and kubeconfigs apart so you never accidentally test with the wrong identity.

### 1. Deploy the infrastructure (Part 1)

Personal tab:

```bash
az login                                    # personal account
az account show --query "{subscription:name, id:id, user:user.name}" -o table

cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars                       # subscription_id, student_name

terraform init
terraform fmt -check
terraform validate
terraform plan -out tfplan
terraform apply tfplan                      # AKS takes ~5-10 minutes
```

Verify:

```bash
source scripts/user-session.sh

az aks show -g "$RG" -n "$AKS" --query "{k8s:kubernetesVersion, azureRbac:aadProfile.enableAzureRbac, managedAad:aadProfile.managed, localAccountsDisabled:disableLocalAccounts, identity:identity.type}" -o table

# kubelet identity (Part 3)
az aks show -g "$RG" -n "$AKS" --query identityProfile.kubeletidentity -o json

# AcrPull on the registry is assigned to the kubelet identity
az role assignment list --scope "$(terraform output -raw acr_id)" --query "[].{role:roleDefinitionName, principal:principalId, type:principalType}" -o table
terraform output kubelet_identity_object_id   # matches the principal above

# Part 2 IDs for the report
terraform output tenant_id
terraform output sp_client_id
terraform output sp_object_id
```

### 2. Push the test image to ACR (Part 7 prep)

Personal tab (your account is subscription Owner, which can push to a registry using standard RBAC):

```bash
sudo service docker start 2>/dev/null || true
az acr login --name "$(terraform output -raw acr_name)"

docker build -t "$ACR_LOGIN_SERVER/hello-web:v1" app/
docker push "$ACR_LOGIN_SERVER/hello-web:v1"

az acr repository list -n "$(terraform output -raw acr_name)" -o table
az acr repository show-tags -n "$(terraform output -raw acr_name)" --repository hello-web -o table
```

### 3. Stage A: service principal with no roles (Parts 2 and 4)

Service principal tab:

```bash
cd ~/uvu-it3200-terraform-aks-identity
source scripts/sp-session.sh

# Step 1: authenticate. --allow-no-subscriptions because the SP has no roles yet.
az login --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --password="$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" \
  --allow-no-subscriptions --output none

az account show --query "{user:user.name, type:user.type, tenant:tenantId}" -o table
az account get-access-token --query "{tokenExpires:expiresOn}" -o table   # proves authentication; token itself not shown

# Step 2: try to get cluster credentials (the same API az aks get-credentials calls)
az rest --method post \
  --url "https://management.azure.com${AKS_ID}/listClusterUserCredential?api-version=2024-05-01"
```

**Expected:** login and token succeed; `listClusterUserCredential` fails with `AuthorizationFailed`. Authentication worked, authorization did not.

### 4. Stage B: Cluster User role only (Part 4, Troubleshooting Challenge)

Personal tab: set `sp_access_stage = "credentials"` in `terraform.tfvars`, then:

```bash
terraform plan -out tfplan && terraform apply tfplan
```

Wait 1–5 minutes (role assignments take time to propagate). Service principal tab:

```bash
# re-login so the CLI sees the subscription the SP now has access to
az login --service-principal --username "$AZURE_CLIENT_ID" --password="$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" --output none
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# Step 2: get the user kubeconfig (no --admin: local accounts are disabled)
az aks get-credentials -g "$RG" -n "$AKS" --file "$KUBECONFIG" --overwrite-existing

# Step 3: switch kubeconfig to service principal login; kubelogin reads AZURE_CLIENT_ID / AZURE_CLIENT_SECRET
kubelogin convert-kubeconfig -l spn

# Step 4: test
kubectl auth whoami            # Kubernetes sees the SP identity -> authentication works
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
kubectl get pods -A
kubectl auth can-i list pods -n hello-web
```

**Expected:** `auth whoami` shows the SP; everything else is `Forbidden` / `no`. The SP is valid. It is missing Kubernetes authorization. The Cluster User role only allows downloading the kubeconfig.

### 5. Stage C: compare with your personal account (Part 6)

Personal tab, with `operator_access_enabled` still `false`:

```bash
source scripts/user-session.sh
az aks get-credentials -g "$RG" -n "$AKS" --file "$KUBECONFIG" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

kubectl auth whoami
kubectl get namespaces          # Forbidden, even though you are subscription Owner

# Inspect the evidence
az role assignment list --assignee "$(terraform output -raw sp_object_id)" --all --query "[].{role:roleDefinitionName, scope:scope}" -o table
az aks show -g "$RG" -n "$AKS" --query "{azureRbac:aadProfile.enableAzureRbac, localAccountsDisabled:disableLocalAccounts}" -o table
```

Owner is a management-plane role (`actions: *`) with **no Kubernetes dataActions**, and Azure RBAC for Kubernetes only honours dataActions. So the problem is the cluster's authorization model, not the service principal.

Now give your account the minimum it needs as the platform operator. Set `operator_access_enabled = true`, apply, wait a few minutes, then:

```bash
kubectl get namespaces                      # works (RBAC Reader, cluster scope)
kubectl apply -f k8s/namespace.yaml         # works (custom "AKS Namespace Provisioner" role)
kubectl auth can-i create deployments -n hello-web   # no: the operator is not the deployer
kubectl get nodes                           # Forbidden: RBAC Reader does not include nodes
```

### 6. Stage D: give the SP its deployer roles (Part 5)

Personal tab: set `sp_access_stage = "deployer"`, apply, wait a few minutes. Service principal tab:

```bash
kubectl get namespaces                               # works
kubectl get pods -A                                  # works (read-only, cluster-wide)
kubectl get nodes                                    # still Forbidden, by design
kubectl auth can-i create deployments -n hello-web   # yes
kubectl auth can-i create deployments -n default     # no
kubectl auth can-i get secrets -n kube-system        # no
kubectl auth can-i create namespaces                 # no
```

### 7. Deploy the app from ACR (Part 7)

Service principal tab:

```bash
envsubst '${ACR_LOGIN_SERVER}' < k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/service.yaml

kubectl rollout status deployment/hello-web -n hello-web
kubectl get deployments,pods,services -n hello-web -o wide
kubectl describe pod -n hello-web -l app=hello-web | grep -A12 Events   # "Successfully pulled image ...azurecr.io/hello-web:v1"
kubectl get events -n hello-web --sort-by=.lastTimestamp

kubectl port-forward -n hello-web svc/hello-web 8080:80
# open http://localhost:8080 in the Windows browser, Ctrl+C to stop
```

For the comparison table, try the same deploy from the personal tab: it is `Forbidden` because the operator has no write access to `hello-web`.

### 8. Optional bonus: break and fix image pulls

Personal tab: set `kubelet_acr_pull_enabled = false`, apply, wait ~5 minutes. Service principal tab:

```bash
envsubst '${ACR_LOGIN_SERVER}' < k8s/bonus-pull-test.yaml | kubectl apply -f -
kubectl get pod pull-test -n hello-web -w          # ErrImagePull -> ImagePullBackOff
kubectl describe pod pull-test -n hello-web | grep -A10 Events   # 401 / unauthorized from the registry
```

The node may still have a cached registry token, so the failure can take a while to appear. If it keeps pulling, delete the pod, wait several more minutes, and retry, and note the caching in your findings. Then set `kubelet_acr_pull_enabled = true`, apply, and recreate the pod:

```bash
kubectl delete pod pull-test -n hello-web
envsubst '${ACR_LOGIN_SERVER}' < k8s/bonus-pull-test.yaml | kubectl apply -f -
kubectl get pod pull-test -n hello-web             # Running
kubectl delete pod pull-test -n hello-web
```

### 9. Clean up

Service principal tab:

```bash
az logout
rm -rf ~/.azure-sp ~/.kube/m9-sp.kubeconfig
```

Personal tab:

```bash
terraform plan -destroy        # review: only lab resources
terraform destroy

az group list --query "[?contains(name, 'uvu-it3200')].name" -o tsv          # nothing (MC_ node RG goes too)
az ad app list --display-name sp-uvu-it3200-douglas --query "[].appId" -o tsv  # nothing
az role definition list --custom-role-only true --query "[?contains(roleName, 'IT3200')].roleName" -o tsv  # nothing
rm -f ~/.kube/m9-user.kubeconfig tfplan
```

---

## Evidence checklist

| Screenshot | Where |
|---|---|
| Successful Terraform deployment | `terraform apply` summary (step 1) |
| AKS cluster in Azure | Portal → Kubernetes services, and the `az aks show` table |
| ACR and stored image | Portal → Container registry → Repositories, and `az acr repository show-tags` |
| Service principal and role assignments | Portal → Entra ID → App registrations; `az role assignment list --assignee <sp_object_id>` |
| Kubelet identity AcrPull | Portal → Container registry → Access control (IAM) → Role assignments |
| SP kubectl results | Steps 3, 4 and 6 |
| Personal account comparison | Step 5 |
| Running pods and deployment | Step 7 |
| App in the browser | Step 7 port-forward |
| Errors and fixes | Forbidden (steps 4/5), AuthorizationFailed (step 3), ImagePullBackOff (bonus) |

Record results in [docs/testing-results.md](docs/testing-results.md).

## Security notes

- No secrets in the repo. `*.tfstate`, `*.tfvars`, kubeconfigs and keys are gitignored. **The client secret is stored in Terraform state**, so the state file is as sensitive as the secret.
- The secret is never printed: `sp-session.sh` reads it into an environment variable. Don't screenshot `env` or the `terraform output -raw sp_client_secret` command output.
- AKS local accounts are disabled, so there is no static admin kubeconfig that bypasses Entra ID and Azure RBAC.
- No identity has Owner on a resource it does not need, and nobody has Cluster Admin.
- Before pushing, check history: `git log -p | grep -iE "secret|password|client_secret" || echo clean`.

## AI assistance

_Document the AI tools, prompts, and how you verified the output here (required by the assignment)._
