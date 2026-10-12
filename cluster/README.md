# Cluster

Everything running in Kubernetes is managed by Argo CD from this directory.
After the one-time bootstrap below, changes happen only through git: never
`kubectl apply`, `helm` or `kubectl edit` against the cluster.

| Path | Contents |
|---|---|
| [`apps/`](apps) | One Argo CD `Application` per component, synced by `root` |
| [`apps/root.yaml`](apps/root.yaml) | App-of-apps: syncs `apps/`, including itself |
| [`configs/`](configs) | What the Applications deploy: kustomizations, Helm values, manifests |

| Application | Deploys | Namespace |
|---|---|---|
| `root` | the Applications in `apps/` | `argocd` |
| `argocd` | Argo CD v3.5.5 managing itself (kustomize: upstream manifests + patches) | `argocd` |
| `cilium` | Cilium 1.20.2 (CNI, kube-proxy replacement) | `kube-system` |
| `gateway-api` | Gateway API CRDs v1.6.3 (standard channel) | cluster-wide |
| `agentgateway-crds` | agentgateway's own CRDs, v1.6.0 | cluster-wide |
| `agentgateway` | agentgateway v1.6.0, the Gateway API implementation (GatewayClass `agentgateway`) | `agentgateway-system` |

Traffic into the cluster goes through Gateway API (`Gateway`, `HTTPRoute`,
...) served by agentgateway. Don't use `Ingress` resources.

Adding a component: add its config under `configs/<name>/` and an Application
in `apps/<name>.yaml`, then push. `root` picks it up.

## Bootstrap runbook

Run once on a fresh cluster. Only Cilium and a basic Argo CD are installed by
hand; Argo CD installs everything else.

Prerequisites:

- The Talos runbook ([`talos/README.md`](../talos/README.md)) is done: the node
  is registered and `NotReady`, because there's no CNI yet.
- This repo is pushed to `https://github.com/ehakan/homelab` (public) with
  this directory on `main`. Argo CD syncs from there, not from your machine.
- Run from the repo root with mise activated (pinned `helm`, `KUBECONFIG`).

The versions below must match `apps/cilium.yaml` and
`configs/argocd/kustomization.yaml`, so that Argo CD adopts exactly what was
installed.

### 1. Cilium

```sh
helm template cilium cilium --repo https://helm.cilium.io --version 1.20.2 \
  --namespace kube-system \
  --values cluster/configs/cilium/values.yaml \
  | kubectl apply --server-side -f -

kubectl -n kube-system rollout status daemonset/cilium
kubectl -n kube-system rollout status deployment/cilium-operator
kubectl get nodes   # Ready
```

### 2. Basic Argo CD

The unpatched upstream manifests, just enough to run the root app. Step 4
applies the patched version of the same manifests in place.

```sh
kubectl create namespace argocd
kubectl apply --server-side --namespace argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/install.yaml

kubectl -n argocd rollout status deployment/argocd-repo-server
kubectl -n argocd rollout status statefulset/argocd-application-controller
```

### 3. Root app

```sh
kubectl apply -f cluster/apps/root.yaml
```

This is the last manual change to the cluster.

### 4. Argo CD takes over

`root` creates the other Applications:

- `argocd` and `cilium` adopt what steps 1–2 installed. `argocd` applies the
  patches from [`configs/argocd/`](configs/argocd), which restarts the Argo CD
  pods.
- `gateway-api`, `agentgateway-crds` and `agentgateway` are installed fresh.
  `agentgateway` may fail its first sync attempts until the CRDs exist, then
  succeeds on retry.

Wait until everything is `Synced` and `Healthy`:

```sh
kubectl -n argocd get applications --watch
kubectl get gatewayclass agentgateway   # created by the agentgateway controller
```

### 5. Log in

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward service/argocd-server 8080:80
```

Open http://localhost:8080 and log in as `admin`. After changing the password,
delete the `argocd-initial-admin-secret` Secret.

## Upgrading a component

- Helm-based apps: bump `targetRevision` in `apps/<name>.yaml`.
- Kustomize-based apps: bump the version in the remote URL in
  `configs/<name>/kustomization.yaml` (`argocd`, `gateway-api`).

Then push. Check compatibility first: Gateway API must stay on a version
agentgateway supports.

## Not set up yet

- **A Gateway.** No `Gateway` exists yet, so nothing is reachable from outside
  the cluster. It needs a LoadBalancer IP (Cilium LB IPAM + L2 announcements,
  with an address range from the LAN) and TLS certificates.
- **Exposing Argo CD.** Port-forward only, until it gets an `HTTPRoute` on the
  Gateway.
- **AppProjects.** Everything uses the built-in `default` project.
