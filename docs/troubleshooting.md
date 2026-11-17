# Troubleshooting scenarios (Part 8)

Three required scenarios plus one extra. The method for each: gather evidence first, form a hypothesis, change one thing, verify.

## Scenario A — Authentication succeeds, Kubernetes access fails

**Possible root causes**
- The identity has no Kubernetes data-plane role (only Cluster User Role, or only management roles like Owner).
- The role exists but at the wrong scope (another namespace, another cluster).
- The role was just assigned and hasn't propagated (up to ~5 minutes).
- The cluster uses native Kubernetes RBAC and there is no RoleBinding for this identity.

**Tools / commands**
```bash
kubectl auth whoami                                   # who does Kubernetes think I am?
kubectl auth can-i list pods -n <ns>                  # yes/no for the exact request
az role assignment list --assignee <object-id> --all -o table
az aks show -g <rg> -n <aks> --query "{azureRbac:aadProfile.enableAzureRbac, localAccountsDisabled:disableLocalAccounts}"
```

**Confirming evidence:** `auth whoami` returns the expected identity (so authentication is fine), the error says `User "<id>" cannot list resource "pods" ... in the namespace`, and the role assignment list has no AKS RBAC role covering that namespace.

**Resolution:** add the narrowest role that covers the operation (here RBAC Reader at cluster scope, RBAC Writer at namespace scope) through Terraform, wait for propagation, re-test with `kubectl auth can-i`.

**Prevention:** define access per identity in code, review it in pull requests, and add a post-deploy smoke test that runs `kubectl auth can-i` for the operations each pipeline needs.

## Scenario B — ImagePullBackOff

**Possible root causes**
- Wrong registry hostname, repository or tag (typo, tag never pushed).
- Kubelet identity has no `AcrPull` (or it was assigned to the SP / cluster identity instead).
- Registry uses ABAC mode, so `AcrPull` no longer works and a repository role is needed.
- Network/DNS: registry firewall or private endpoint the nodes cannot reach.

**Tools / commands**
```bash
kubectl describe pod <pod> -n <ns>            # Events show the exact pull error
kubectl get events -n <ns> --sort-by=.lastTimestamp
az acr repository show-tags -n <acr> --repository <repo>
az aks show -g <rg> -n <aks> --query identityProfile.kubeletidentity.objectId -o tsv
az role assignment list --scope <acr-id> -o table
az aks check-acr -g <rg> -n <aks> --acr <acr>.azurecr.io    # end-to-end test from a node
```

**Confirming evidence:** the event text tells the two big cases apart.
- `not found` / `manifest unknown` → the name or tag is wrong (registry answered, image doesn't exist).
- `401 Unauthorized` / `failed to authorize` → identity problem (registry refused the credential).
- `no such host` / timeout → DNS or network.

**Resolution:** fix the image reference, or assign `AcrPull` on the registry to the **kubelet identity's object ID** via Terraform, then delete the pod so it retries.

**Prevention:** assign AcrPull in the same Terraform config that creates AKS and ACR (as this repo does), pin image tags (or digests) produced by CI, and run `az aks check-acr` in the pipeline.

## Scenario D — "Just give every service principal Cluster Admin"

**Why it's tempting:** authorization errors disappear.

**Why it's wrong:** Cluster Admin can read every Secret, create privileged pods, change RBAC, and run code on any node, in every namespace. Every pipeline credential becomes a full cluster takeover credential, you lose the ability to tell from logs which identity was supposed to do what, and one leaked secret compromises all applications.

**What to do instead:** treat the Forbidden error as data. Read which verb/resource/namespace was denied, grant that (scoped to the namespace) through Terraform, and use `kubectl auth can-i` to verify. If something truly needs elevated rights, make it temporary and audited (PIM / just-in-time access) and remove it afterwards.

**Prevention:** policy-as-code in CI (e.g. Checkov/tfsec or Azure Policy) that fails any plan assigning Cluster Admin or Owner to a service principal.

## Scenario E — Terraform succeeds but the app won't start

**Possible root causes:** Terraform only proves the Azure resources exist. The workload can still fail on image pull (Scenario B), insufficient node CPU/memory (`Pending`), the container crashing (`CrashLoopBackOff`), failing readiness/liveness probes, or a Pod Security violation (pod rejected).

**Tools:** `kubectl get pods -o wide`, `kubectl describe pod`, `kubectl logs <pod> --previous`, `kubectl get events`, `kubectl get rs -n <ns>` (rejected pods show on the ReplicaSet), `kubectl top nodes`.

**Evidence → cause**
| Status | Meaning |
|---|---|
| `Pending` | Not scheduled: no node has enough requested CPU/memory, or taints/affinity block it |
| `ErrImagePull` | The first pull attempt failed |
| `ImagePullBackOff` | Pulls keep failing; kubelet is waiting longer between retries |
| `CrashLoopBackOff` | Image pulled and started, but the process keeps exiting; check `kubectl logs --previous` |

**Prevention:** deployment tests after `terraform apply` (`kubectl rollout status` with a timeout), resource requests sized to the node pool, and probes that match the app.

## Bonus question — catching permission problems before production

- `terraform validate` + `terraform plan` in CI, with the plan reviewed in the pull request.
- Static security scanning of the Terraform (Checkov, tfsec/Trivy config, or OPA/Conftest policies): block `Owner`, `Contributor` at subscription scope, `Cluster Admin` for SPs, ACR admin user enabled, local accounts enabled.
- Deploy to a short-lived test environment from the same code and run smoke tests: `az aks check-acr`, a pull-test pod with `imagePullPolicy: Always`, `kubectl auth can-i` for each pipeline identity, and `kubectl rollout status`.
- Promote the exact same Terraform and image digest to production only after those pass.
