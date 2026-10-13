# Cluster

Everything running in Kubernetes is managed by Argo CD from this directory.
After the one-time bootstrap below, changes happen only through git: never
`kubectl apply`, `helm` or `kubectl edit` against the cluster.

| Path                               | Contents                                                             |
| ---------------------------------- | -------------------------------------------------------------------- |
| [`apps/`](apps)                    | One Argo CD `Application` per component, synced by `root`            |
| [`apps/root.yaml`](apps/root.yaml) | App-of-apps: syncs `apps/`, including itself                         |
| [`configs/`](configs)              | What the Applications deploy: kustomizations, Helm values, manifests |

| Application          | Deploys                                                                                          | Namespace             |
| -------------------- | ------------------------------------------------------------------------------------------------ | --------------------- |
| `root`               | the Applications in `apps/`                                                                      | `argocd`              |
| `argocd`             | Argo CD v3.5.5 managing itself (kustomize: upstream manifests + patches)                         | `argocd`              |
| `cilium`             | Cilium 1.20.2 (CNI, kube-proxy replacement), LAN LoadBalancer IPs `192.168.11.200–230`           | `kube-system`         |
| `gateway-api`        | Gateway API CRDs v1.6.3 (standard channel)                                                       | cluster-wide          |
| `agentgateway-crds`  | agentgateway's own CRDs, v1.6.0                                                                  | cluster-wide          |
| `agentgateway`       | agentgateway v1.6.0, the Gateway API implementation (GatewayClass `agentgateway`)                | `agentgateway-system` |
| `cert-manager`       | cert-manager v1.21.2, with Gateway API support, and the Let's Encrypt ClusterIssuers             | `cert-manager`        |
| `external-secrets`   | External Secrets Operator 2.12.0 and the 1Password ClusterSecretStores (see [Secrets](#secrets)) | `external-secrets`    |
| `gateways`           | The `internal` and `public` Gateways and their certificates (see [Gateways](#gateways))          | `gateway`             |
| `tailscale-operator` | Tailscale operator 1.102.4 and the subnet router for the tailnet                                 | `tailscale`           |

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
- The 1Password service accounts for External Secrets exist (see
  [Secrets](#secrets)) and `op` is signed in.

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

The unpatched upstream manifests, just enough to run the root app. Step 5
applies the patched version of the same manifests in place.

```sh
kubectl create namespace argocd
kubectl apply --server-side --namespace argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/install.yaml

kubectl -n argocd rollout status deployment/argocd-repo-server
kubectl -n argocd rollout status statefulset/argocd-application-controller
```

### 3. 1Password service account tokens

The only Secrets not managed through git. External Secrets reads every other
secret from 1Password with them. Make sure the service accounts exist before execution.

```fish
kubectl create namespace external-secrets
for vault in homelab-cluster homelab-management
  # --no-newline: a trailing newline breaks the token.
  op read --no-newline "op://homelab-bootstrap/external-secrets-$vault/credential" \
    | kubectl -n external-secrets create secret generic onepassword-$vault \
        --from-file=token=/dev/stdin
end
```

### 4. Root app

```sh
kubectl apply -f cluster/apps/root.yaml
```

This is the last manual change to the cluster.

### 5. Argo CD takes over

`root` creates the other Applications:

- `argocd` and `cilium` adopt what steps 1–2 installed. `argocd` applies the
  patches from [`configs/argocd/`](configs/argocd), which restarts the Argo CD
  pods.
- Everything else is installed fresh. Apps that depend on another app's CRDs
  or webhooks (`cilium`'s IP pool, `cert-manager`'s issuers, `gateways`,
  `tailscale-operator`, `agentgateway`, `external-secrets`) may fail their first
  sync attempts, then succeed on retry.
- The 1Password items the issuers and the Tailscale operator read are created
  by [`terraform/`](../terraform): apply it first.

Wait until everything is `Synced` and `Healthy`:

```sh
kubectl -n argocd get applications --watch
kubectl get gatewayclass agentgateway   # created by the agentgateway controller
kubectl get clustersecretstores   # both Valid, Ready
kubectl -n gateway get gateways,certificates   # Programmed, Ready
kubectl get connector subnet-router   # Ready
```

cert-manager only enables its Gateway API support if the Gateway API CRDs
existed when it started. If it came up first, it logs that the CRDs are
missing; restart it once they exist:

```sh
kubectl -n cert-manager rollout restart deployment/cert-manager
```

### 6. Log in

Once `gateways` is synced, Argo CD is at <https://argocd.lab.ehakan.dev> (LAN
and tailnet), for the UI and the CLI. Log in as `admin`, password from the
1Password item `argocd-admin` in `homelab-management`
([`configs/argocd/admin-password.yaml`](configs/argocd/admin-password.yaml)):

```sh
argocd login argocd.lab.ehakan.dev --username admin \
  --password "$(op read 'op://homelab-management/argocd-admin/password')"
```

Argo CD also generates `argocd-initial-admin-secret` on first start; it's
unused, delete it:

```sh
kubectl -n argocd delete secret argocd-initial-admin-secret
```

## Secrets

Secrets live in 1Password and reach the cluster through External Secrets.
Never put a Secret manifest in git; write an `ExternalSecret` that references
one of the ClusterSecretStores (example in
[`configs/external-secrets/secretstores/homelab-cluster.yaml`](configs/external-secrets/secretstores/homelab-cluster.yaml)).

| 1Password vault      | Contents                                                | ClusterSecretStore   | Usable from                                                                                     |
| -------------------- | ------------------------------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------- |
| `homelab-bootstrap`  | Talos sops key, External Secrets service account tokens | none                 | never read by the cluster                                                                       |
| `homelab-management` | API tokens, admin credentials                           | `homelab-management` | namespaces listed in [its store](configs/external-secrets/secretstores/homelab-management.yaml) |
| `homelab-cluster`    | application secrets                                     | `homelab-cluster`    | every namespace                                                                                 |

- Keys are `<item>/<field>` or `<item>/<section>/<field>`. Item names must be
  unique within the vault.
- Use `refreshInterval: 1h` unless a secret needs to change faster: service
  account reads are rate-limited per hour.

One-time 1Password setup (before the bootstrap):

One read-only service account per vault, each token saved straight into
`homelab-bootstrap` as an API Credential item `external-secrets-<vault>`
(field `credential`). The token is only shown once, and a service account's
vault access can't be changed later: to change it, create a new one.

```fish
op vault create homelab-management
op vault create homelab-cluster

for vault in homelab-cluster homelab-management
  set -l token (op service-account create external-secrets-$vault --vault $vault:read_items --raw)
  op item create --vault homelab-bootstrap --category 'API Credential' \
    --title external-secrets-$vault "credential=$token"
  set -e token
end
```

Never grant a service account access to `homelab-bootstrap`.

Argo CD's `admin` password, in `homelab-management`:

```sh
op item create --vault homelab-management --category login --title argocd-admin \
  --url https://argocd.lab.ehakan.dev --generate-password=40,letters,digits username=admin
```

Rotating a token: create a new one, update the 1Password item, delete the
`onepassword-<vault>` Secret in `external-secrets`, and recreate it with step 3
of the runbook.

## Upgrading a component

- Helm-based apps: bump `targetRevision` in `apps/<name>.yaml`.
- Kustomize-based apps: bump the version in the remote URL in
  `configs/<name>/kustomization.yaml` (`argocd`, `gateway-api`).

Then push. Check compatibility first: Gateway API must stay on a version
agentgateway supports.

## Gateways

All homelab hostnames are `*.lab.ehakan.dev`. Two Gateways in the `gateway`
namespace, each with its own LAN IP and certificate:

| Gateway    | IP               | Reachable from                                                      | Routes from                                                      |
| ---------- | ---------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `internal` | `192.168.11.200` | LAN (router DNS), tailnet (subnet router, split DNS to the router)  | any namespace                                                    |
| `public`   | `192.168.11.201` | internet (router port-forward)                                      | namespaces labelled `gateway.lab.ehakan.dev/public: "true"` only |

A private service is an `HTTPRoute` with `parentRefs: [{name: internal,
namespace: gateway, sectionName: https}]` and a hostname under
`lab.ehakan.dev`. A public one also attaches to `public`, so at home it's
still served by `internal`. HTTP on port 80 redirects to HTTPS on both.

Certificates come from Let's Encrypt (`letsencrypt-production`) via DNS-01 on
Cloudflare, see
[`configs/gateways/certificates.yaml`](configs/gateways/certificates.yaml).

Outside the cluster:

- Router DNS: `*.lab.ehakan.dev` → `192.168.11.200` (manual, router config).
- Router port-forward: 443 and 80 → `192.168.11.201` (manual, once there's a
  public service).
- Public DNS and the Tailscale side: [`terraform/`](../terraform).

## Not set up yet

- **AppProjects.** Everything uses the built-in `default` project.
