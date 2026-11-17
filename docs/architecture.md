# Architecture

There are **two separate access flows**. They use different identities, and permission on one does nothing for the other.

![Architecture diagram](architecture.png)

Source (renders on GitHub):

```mermaid
flowchart LR
    subgraph ENTRA["Microsoft Entra ID"]
        SP["Service principal<br/>sp-uvu-it3200-douglas<br/><i>app deployer</i>"]
        USER["Personal user account<br/><i>platform operator</i>"]
    end

    subgraph RG["Resource group rg-uvu-it3200-douglas"]
        subgraph AKS["AKS aks-uvu-it3200-douglas"]
            API["Kubernetes API server<br/>Entra authN + Azure RBAC authZ"]
            subgraph NS["namespace hello-web"]
                DEP["Deployment hello-web<br/>2 pods"] --- SVC["Service hello-web<br/>ClusterIP :80"]
            end
            NODE["Node / kubelet<br/>runs as kubelet<br/>managed identity"]
        end
        ACR[("ACR acruvuit3200douglas<br/>hello-web:v1<br/>admin user off")]
        CID["Cluster managed identity<br/>manages LB, disks, NICs"]
    end

    SP -- "① kubelogin spn (client secret)<br/>Cluster User Role: cluster<br/>RBAC Reader: cluster<br/>RBAC Writer: hello-web only" --> API
    USER -- "① kubelogin azurecli<br/>RBAC Reader: cluster<br/>custom Namespace Provisioner" --> API
    API -- "② create Deployment<br/>(if Azure RBAC allows)" --> NS
    API -- "③ schedule pods" --> NODE
    NODE -- "④ pull image<br/>AcrPull: registry" --> ACR
    CID -. "AKS control plane" .- AKS
```

## Flow 1: Kubernetes API access (people and automation)

1. The caller signs in to **Microsoft Entra ID**. The service principal uses its client ID + secret (`kubelogin -l spn`), your account uses the Azure CLI session (`kubelogin -l azurecli`). This is **authentication**.
2. kubectl sends the Entra token to the AKS API server. Because the cluster has **Azure RBAC for Kubernetes authorization** enabled and local accounts disabled, the API server asks Azure RBAC whether the identity has a role whose *dataActions* allow the request (for example `.../namespaces/hello-web` + `apps/deployments/write`). This is **authorization**.
3. If allowed, the Deployment is created and the scheduler places pods on the node.

## Flow 2: Image pull (the cluster itself)

4. The kubelet on the node needs the image `acruvuit3200douglas.azurecr.io/hello-web:v1`. It authenticates to ACR as the **kubelet managed identity**, which has `AcrPull` on the registry. The service principal is not involved at all.

## Plain-language version

- **Entra ID** is the company badge office: it proves who you are.
- **Azure RBAC role assignments** are the access list on each door.
- The **service principal** is the deployment robot's badge. It can open the `hello-web` room and look through the windows of other rooms, but it cannot build new rooms or open the server closet (nodes).
- **Your account** is the building operator: it can see the building and create new rooms, but it does not move furniture inside the app room.
- The **kubelet identity** is the delivery truck's badge: it can only pick up packages (images) from the warehouse (ACR).
- The **cluster identity** is the facilities crew: it manages the cluster's own Azure plumbing (load balancer, disks).
