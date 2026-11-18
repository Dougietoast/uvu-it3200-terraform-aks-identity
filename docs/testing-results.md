# Testing results (Nov 17, 2026)

Region `westus2`, node `Standard_D2als_v7`, Kubernetes 1.36.5. Resources destroyed afterward (`Destroy complete! Resources: 14 destroyed`).

## Service principal vs personal account (final state)

| Test | Service principal | Personal account |
|---|---|---|
| Azure authentication | ✅ `az login --service-principal`, `servicePrincipal` | ✅ browser `az login` |
| Retrieve AKS credentials | ✅ Cluster User Role | ✅ (subscription Owner) |
| `kubectl auth whoami` | ✅ `e9dfa240-…` | ✅ `eb7f7786-…` |
| List Kubernetes namespaces | ✅ RBAC Reader | ✅ RBAC Reader (❌ Forbidden before operator roles, despite Owner) |
| Read pods in `hello-web` | ✅ | ✅ (❌ Forbidden before operator roles) |
| Create namespace `hello-web` | ❌ no | ✅ `namespace/hello-web created` |
| `kubectl get nodes` | ❌ Forbidden | ❌ Forbidden |
| Deploy application | ✅ `deployment.apps/hello-web created` | ❌ `cannot create resource "deployments" … in the namespace "hello-web"` |

## Service principal by stage

| Command | Stage A (`none`) | Stage B (`credentials`) | Stage D (`deployer`) |
|---|---|---|---|
| `az login --service-principal` | ✅ token issued | ✅ | ✅ |
| Get cluster credentials | ❌ `Subscription '79a9c125-…' not found` | ✅ | ✅ |
| `kubectl cluster-info` | n/a | ❌ Forbidden (services in kube-system) | not re-run |
| `kubectl get nodes` | n/a | ❌ Forbidden | ❌ Forbidden (by design) |
| `kubectl get namespaces` | n/a | ❌ Forbidden | ✅ |
| `kubectl get pods -A` | n/a | ❌ Forbidden | ✅ |
| `can-i create deployments -n hello-web` | n/a | ❌ no | ✅ yes |
| `can-i create deployments -n default` | n/a | n/a | ❌ no |
| `can-i get secrets -n kube-system` | n/a | n/a | ❌ no |
| `can-i create namespaces` | n/a | n/a | ❌ no |
| `can-i delete namespaces/hello-web` | n/a | n/a | ❌ no |

With the kubeconfig in `--login spn` mode, `az logout` in the SP tab did not stop `kubectl auth whoami` from working. kubelogin authenticated with the client secret directly.

## Deployment

| Check | Result |
|---|---|
| Rollout | `deployment "hello-web" successfully rolled out`, `2/2` |
| Image pull | `Successfully pulled image "acruvuit3200douglas.azurecr.io/hello-web:v1" in 2.872s … Image size: 25584474 bytes` |
| Startup | two transient `Readiness probe failed … connection refused` before nginx started; both pods then Ready |
| Access | `kubectl port-forward -n hello-web svc/hello-web 8080:80` → page loaded at `http://localhost:8080` |

## Errors and resolutions

| # | Error | Identity | Cause | Fix |
|---|---|---|---|---|
| 1 | `Insufficient privileges to complete the operation` | UVU student account | Tenant blocks app registration | Personal subscription |
| 2 | DSv5 family quota `0` | personal | New subscription quota | Choose a family with quota |
| 3 | `The VM size of Standard_B2s is not allowed in your subscription in location 'westus2'` (also `Standard_D2s_v3`) | personal | AKS allowed-size list, separate from quota | `Standard_D2als_v7` |
| 4 | `Saved plan is stale` | personal | Ctrl+C during apply; cluster created but not in state | `az aks wait --created` + `terraform import` |
| 5 | `Subscription … not found` | SP | No role in the subscription (Stage A) | Cluster User Role |
| 6 | `subscription ID … is not known by Azure CLI` | SP | Terraform run in the SP's tab | Run Terraform only as the personal account |
| 7 | `--client-id is required`, `--tenant-id is required` | SP | Azure CLI auto-converted kubeconfig to `azurecli` | Pass both flags to `kubelogin convert-kubeconfig -l spn` |
| 8 | `deployment.apps/hello-web unchanged (server dry run)` | personal | `apply` sent no write, so nothing was authorized | `kubectl create deployment … --dry-run=server` → Forbidden |

## Bonus: image pull break/fix

Not performed.
