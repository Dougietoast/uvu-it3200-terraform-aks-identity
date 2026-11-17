# Identities and permissions

## The four identities

| Identity | What it is | Credential | Used for in this lab |
|---|---|---|---|
| Personal Entra user | A human account in the tenant | Password + MFA through `az login` | Running Terraform, pushing the image, creating the namespace |
| Service principal (`sp-uvu-it3200-douglas`) | The tenant-local identity of an app registration | Client secret (lab), certificate, or federated credential | Automated deployments to Kubernetes |
| AKS cluster managed identity | System-assigned identity owned by the AKS resource | Managed by Azure, no secret to handle | AKS managing its own Azure resources (load balancer, public IP, disks) |
| AKS kubelet managed identity | User-assigned identity AKS creates in the node resource group | Managed by Azure, available on the nodes | Nodes pulling images from ACR |

**Why separate identities?** Each one does a different job and has a different blast radius. If the deployment secret leaks, the attacker can only touch one namespace. If a node is compromised, the kubelet identity can only pull images. Giving every identity the same broad role would mean one leaked credential exposes everything, and the audit logs could no longer tell you which actor did what.

**App registration vs service principal:** the app registration (`azuread_application`) is the global definition of the app. The service principal (`azuread_service_principal`) is that app's identity inside this tenant. Role assignments reference the **service principal object ID**, not the application (client) ID. The client ID is what you log in with.

## How the service principal authenticates

1. `az login --service-principal --username <client_id> --password=<secret> --tenant <tenant_id>` gets a token for Azure Resource Manager (used for `az aks get-credentials`).
2. `kubelogin convert-kubeconfig -l spn` rewrites the kubeconfig so kubectl calls kubelogin, which exchanges the same client ID + secret (from `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET`) for a token whose audience is the AKS Entra server application.
3. The secret is created by Terraform with a 7-day lifetime (`time_rotating`), is never committed, and is never printed. It does live in `terraform.tfstate`, which is gitignored.

In production I would not use a client secret at all: a CI/CD pipeline would use **workload identity federation (OIDC)**, so there is no long-lived secret to leak or rotate.

## Role assignments (all in `rbac.tf`)

| Principal | Role | Scope | Why |
|---|---|---|---|
| Kubelet identity | `AcrPull` | Registry | Nodes must authenticate to pull from a private registry. Pull only. |
| Service principal | Azure Kubernetes Service Cluster User Role | AKS cluster | Allows `listClusterUserCredential` (`az aks get-credentials`). Grants **no** Kubernetes permissions. |
| Service principal | Azure Kubernetes Service RBAC Reader | AKS cluster | Read most objects in all namespaces, excluding Secrets, roles and nodes. Lets the deployer see what is running. |
| Service principal | Azure Kubernetes Service RBAC Writer | `.../namespaces/hello-web` | Create/update Deployments, Services, Pods, ConfigMaps in the app namespace only. |
| Personal user | Azure Kubernetes Service RBAC Reader | AKS cluster | Operator visibility. |
| Personal user | **AKS Namespace Provisioner** (custom) | AKS cluster | Only `namespaces/read` and `namespaces/write`. Lets the operator create the namespace without Cluster Admin. |

The personal user is also subscription **Owner** (that is how Terraform can create everything). Owner has `actions: *` but no `dataActions`, so it grants **zero** Kubernetes API access when Azure RBAC for Kubernetes is enabled. Step 5 of the README demonstrates this.

### Roles considered and rejected

| Role | Verdict |
|---|---|
| AcrPush (for the kubelet) | Nodes never push. Push would let a compromised node replace images other workloads run. |
| Contributor on the registry | Management plane: could delete the registry, change network rules, enable the admin user. Far beyond pulling. |
| Container Registry Repository Reader | The ABAC equivalent of AcrPull. Only needed when the registry's role assignment mode is `AbacRepositoryPermissions`; in that mode `AcrPull` stops working and permissions can be limited to specific repositories. This registry uses `LegacyRegistryPermissions`, so `AcrPull` is correct. |
| AKS RBAC Admin | Everything in its scope including roles/rolebindings (except namespace and quota writes). More than a deployer needs. |
| AKS RBAC Cluster Admin | Full control of the whole cluster. Explicitly not used. |
| RBAC Writer at cluster scope | Would let the SP write in `kube-system` and every other namespace. Scoped to `hello-web` instead. |

### Azure RBAC for Kubernetes vs native Kubernetes RBAC

| | Azure RBAC for Kubernetes (used here) | Native Kubernetes RBAC |
|---|---|---|
| Where permissions live | Azure role assignments (ARM) | `Role`/`ClusterRole` + `RoleBinding` objects inside the cluster |
| Managed with | Terraform `azurerm_role_assignment` | `kubectl apply`, or Terraform's kubernetes provider |
| Identity | Entra users, groups, SPs, managed identities | Same Entra identities (subjects are object IDs / group IDs), plus Kubernetes ServiceAccounts |
| Auditing | Azure Activity Log + Entra | Kubernetes audit log |
| Scale | Same model across many clusters, assignable at subscription/RG/cluster/namespace | Must be applied per cluster |

Both are active on this cluster: the API server checks Kubernetes RBAC and the Azure RBAC webhook, and either can allow a request. That is why `kubectl auth whoami` works with no Azure roles (the built-in `system:basic-user` ClusterRole allows self-reviews for any authenticated user).

## Security design questions

**Why can the deployer create Deployments in one namespace but not delete the cluster?** Deleting the cluster is an Azure management-plane action (`Microsoft.ContainerService/managedClusters/delete`) that none of its roles include, and creating Deployments is a Kubernetes data-plane action limited to `hello-web`. A deployment pipeline needs to ship one app. If its credential leaks, the worst case is that app's namespace, not every workload and not the infrastructure.

**Dev / test / prod:** separate clusters (or at least separate subscriptions) per environment, one deployer identity per app per environment, each with RBAC Writer only on its namespace in its environment. Production identities are used only by the pipeline, gated by approvals, never by people's day-to-day accounts. Humans get Reader in prod and break-glass admin through Privileged Identity Management (time-limited, approved, audited).
