# Testing results

Fill in as you go. Paste the exact error text (no secrets or tokens).

## Service principal vs personal account

| Test | Service principal | Personal account |
|---|---|---|
| Azure authentication | | |
| Retrieve AKS credentials | | |
| `kubectl auth whoami` | | |
| List Kubernetes namespaces | | |
| Read pods in `hello-web` | | |
| `kubectl get nodes` | | |
| Deploy application | | |

## Service principal by stage

| Command | Stage A (`none`) | Stage B (`credentials`) | Stage D (`deployer`) |
|---|---|---|---|
| `az login --service-principal` | | | |
| `listClusterUserCredential` / `az aks get-credentials` | | | |
| `kubectl cluster-info` | | | |
| `kubectl get nodes` | | | |
| `kubectl get namespaces` | | | |
| `kubectl get pods -A` | | | |
| `kubectl auth can-i create deployments -n hello-web` | | | |

## Errors and resolutions

| # | Error (exact text) | Identity | Cause | Fix |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

## Bonus: image pull break/fix

| Step | Result |
|---|---|
| `kubelet_acr_pull_enabled = false` applied | |
| Pull-test pod status / event | |
| `kubelet_acr_pull_enabled = true` applied | |
| Pull-test pod after fix | |
