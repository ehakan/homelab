# Cluster

Everything running in Kubernetes is managed by Argo CD from this directory.
After the one-time bootstrap below, changes happen only through git: never
`kubectl apply`, `helm` or `kubectl edit` against the cluster.

| Path                               | Contents                                                             |
| ---------------------------------- | -------------------------------------------------------------------- |
| [`apps/`](apps)                    | One Argo CD `Application` per component, synced by `root`            |
| [`apps/root.yaml`](apps/root.yaml) | App-of-apps: syncs `apps/`, including itself                         |
| [`configs/`](configs)              | What the Applications deploy: kustomizations, Helm values, manifests |

| Application              | Deploys                                                                                                           | Namespace             |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------- | --------------------- |
| `root`                   | the Applications in `apps/`                                                                                       | `argocd`              |
| `argocd`                 | Argo CD v3.5.5 managing itself (kustomize: upstream manifests + patches)                                          | `argocd`              |
| `cilium`                 | Cilium 1.20.2 (CNI, kube-proxy replacement), LAN LoadBalancer IPs `192.168.11.200–230`                            | `kube-system`         |
| `gateway-api`            | Gateway API CRDs v1.6.3 (standard channel)                                                                        | cluster-wide          |
| `agentgateway-crds`      | agentgateway's own CRDs, v1.6.0                                                                                   | cluster-wide          |
| `agentgateway`           | agentgateway v1.6.0, the Gateway API implementation (GatewayClass `agentgateway`)                                 | `agentgateway-system` |
| `cert-manager`           | cert-manager v1.21.2, with Gateway API support, and the Let's Encrypt ClusterIssuers                              | `cert-manager`        |
| `external-secrets`       | External Secrets Operator 2.12.0 and the 1Password ClusterSecretStores (see [Secrets](#secrets))                  | `external-secrets`    |
| `gateways`               | The `internal` and `public` Gateways and their certificates (see [Gateways](#gateways))                           | `gateway`             |
| `tailscale-operator`     | Tailscale operator 1.102.4 and the subnet router for the tailnet                                                  | `tailscale`           |
| `local-path-provisioner` | local-path-provisioner v0.0.37: default StorageClass `local-path`, volumes on the Talos `local-storage` partition | `local-path-storage`  |
| `cloudnative-pg`         | CloudNativePG operator 1.30.1 (chart 0.29.1)                                                                      | `cnpg-system`         |
| `gpu-operator`            | NVIDIA GPU Operator v26.7.2: device plugin, `nvidia` RuntimeClass (driver and toolkit come from Talos)            | `gpu-operator`         |
| `media-base`              | Media stack base: the shared `/data` volume and the `media-postgres` PostgreSQL cluster (see [Media stack](#media-stack)) | `media`                |
| `prowlarr`                | Prowlarr 2.6.5: indexer manager                                                                                   | `media`                |
| `qbittorrent`             | qBittorrent 5.2.4: downloads to `/data/torrents`                                                                  | `media`                |
| `radarr`                  | Radarr 6.4.4: movies                                                                                              | `media`                |
| `sonarr`                  | Sonarr 4.0.20: TV                                                                                                 | `media`                |
| `seerr`                   | Seerr v3.5.0: media requests                                                                                      | `media`                |
| `jellyfin`                | Jellyfin 12.2: media server, NVENC transcoding on hl-tal-tower-01's GTX 1050 Ti                                   | `media`                |
| `cleanuparr`              | Cleanuparr 2.10.11: removes malware (e.g. `.exe`), stalled and failed downloads                                    | `media`                |
| `flaresolverr`            | FlareSolverr v3.5.2: solves Cloudflare challenges for Prowlarr indexers (in-cluster only, no route)               | `media`                |

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
for vault in homelab-cluster homelab-management homelab-generated
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
  patches from [`configs/argocd/`](configs/argocd). Argo CD doesn't reload
  `argocd-cmd-params-cm` by itself; once `argocd` has synced, restart it
  (otherwise apps with Gateway API resources stay `OutOfSync`):

  ```sh
  kubectl -n argocd rollout restart statefulset/argocd-application-controller deployment/argocd-server
  ```

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
| `homelab-generated`  | secrets the cluster generates (read and write)          | `homelab-generated`  | namespaces listed in [its store](configs/external-secrets/secretstores/homelab-generated.yaml)  |

- Keys are `<item>/<field>` or `<item>/<section>/<field>`. Item names must be
  unique within the vault.
- Secrets nobody types in (database passwords, signing keys, OIDC client
  secrets) are generated: a `PushSecret` with `updatePolicy: IfNotExists`
  creates the item in `homelab-generated` once, and `ExternalSecret`s read it
  like any other.
  To rotate one, delete its 1Password item.
- Use `refreshInterval: 1h` unless a secret needs to change faster: service
  account reads are rate-limited per hour.

One-time 1Password setup (before the bootstrap):

One service account per vault, read-only except for `homelab-generated`, each
token saved straight into
`homelab-bootstrap` as an API Credential item `external-secrets-<vault>`
(field `credential`). The token is only shown once, and a service account's
vault access can't be changed later: to change it, create a new one.

```fish
op vault create homelab-management
op vault create homelab-cluster
op vault create homelab-generated

for vault in homelab-cluster homelab-management homelab-generated
  set -l access read_items
  test $vault = homelab-generated; and set access read_items,write_items
  set -l token (op service-account create external-secrets-$vault --vault $vault:$access --raw)
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

## Media stack

Namespace `media`, everything on `hl-tal-tower-01`, following the
[TRaSH Guides](https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Docker/):

- One volume, `media-data`, holds `/data/torrents/{movies,tv}` and
  `/data/media/{movies,tv}`. It's one filesystem, so imports are hardlinks and
  moves are instant. qBittorrent sees `/data/torrents`, Radarr and Sonarr all of
  `/data`, Jellyfin `/data/media`. It's `ReadWriteOnce`, which allows any number
  of pods on the same node.
- Every app runs as `1000:1000` (TRaSH's single shared user).
- Radarr, Sonarr, Prowlarr, Seerr and Cleanuparr use `media-postgres` (CloudNativePG, one
  role and database(s) per app, `configs/media-base/db-*.yaml`). Jellyfin uses
  SQLite. Passwords and the *arr API keys are generated into the 1Password vault
  `homelab-generated` (`<app>-db`, `<app>-api-key`).
- All UIs are at `https://<app>.lab.ehakan.dev` on the `internal` Gateway.

App settings that git can't hold (these versions store them in their own
databases) were set once through each app's API on 2026-10-16. Redo them after
a rebuild, or if an app's config volume or database is lost. Every login is
user `admin`, password in 1Password `homelab-management` → `<app>-admin`
(Seerr signs in with the Jellyfin account). API keys:
`kubectl -n media get secret <app>-api-key -o jsonpath='{.data.api-key}' | base64 -d`.

1. Radarr, Sonarr, Prowlarr: login set via `PUT /api/v{1,3}/config/host`.
2. qBittorrent: login written by its init container on every start (change it
   only in 1Password, then restart the pod). Set through its Web API, per
   [TRaSH](https://trash-guides.info/Downloaders/qBittorrent/Basic-Setup/):
   automatic torrent management, default save path `/data/torrents`, no
   incomplete folder, categories `movies` and `tv` (→ `/data/torrents/<cat>`),
   excluded file names `*.rar`, `*.r[0-9]*`, `*.exe`, `*.lnk`, `*.scr`,
   `*.bat`, `*.cmd`, `*.msi`.
3. Radarr and Sonarr: root folders `/data/media/movies` and `/data/media/tv`;
   download client qBittorrent (`qbittorrent:80`, category `movies` / `tv`).
4. Prowlarr: Radarr (`http://radarr`) and Sonarr (`http://sonarr`) as apps,
   full sync, rejecting blocklisted torrent hashes. Indexer Proxy FlareSolverr
   (`http://flaresolverr:8191/`) with tag `flaresolverr`: give that tag to
   indexers behind Cloudflare. **Indexers: add your own**; they sync to both.
5. Jellyfin: startup wizard (English, US metadata), libraries Movies
   (`/data/media/movies`) and Shows (`/data/media/tv`), transcoding NVENC with
   hardware decoding of H.264, HEVC, MPEG-2, VC-1 and VP9 (10-bit HEVC/VP9),
   tone-mapping, throttling and segment deletion. API calls need the
   `Authorization: MediaBrowser ...` header; Jellyfin 12 rejects
   `X-Emby-Authorization`.
6. Seerr: signed in with Jellyfin's `admin` (Seerr's admin), both libraries
   enabled, Radarr and Sonarr as defaults with quality profile `HD-1080p`.
7. Cleanuparr: qBittorrent, Radarr and Sonarr connected; Malware Blocker on
   for both with the default
   [blacklist](https://raw.githubusercontent.com/Cleanuparr/Cleanuparr/main/blacklist)
   (checks every 5 seconds); Queue Cleaner every 5 minutes, 3 strikes for
   failed imports, errored and stuck-on-metadata downloads. Removed releases
   are blocklisted in Radarr/Sonarr but not re-searched immediately.

## Not set up yet

- **AppProjects.** Everything uses the built-in `default` project.
