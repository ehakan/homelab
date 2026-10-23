# Cluster

Everything running in Kubernetes is managed by Argo CD from this directory.
After the one-time bootstrap below, changes happen only through git: never
`kubectl apply`, `helm` or `kubectl edit` against the cluster.

| Path                               | Contents                                                             |
| ---------------------------------- | -------------------------------------------------------------------- |
| [`apps/`](apps)                    | One Argo CD `Application` per component, synced by `root`            |
| [`apps/root.yaml`](apps/root.yaml) | App-of-apps: syncs `apps/`, including itself                         |
| [`configs/`](configs)              | What the Applications deploy: kustomizations, Helm values, manifests |

| Application                 | Deploys                                                                                                                       | Namespace                   |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| `root`                      | the Applications in `apps/`                                                                                                   | `argocd`                    |
| `homelab-private`           | the Applications in [ehakan/homelab-private](https://github.com/ehakan/homelab-private) `cluster/apps/` (private)             | `argocd`                    |
| `argocd`                    | Argo CD v3.5.5 managing itself (kustomize: upstream manifests + patches)                                                      | `argocd`                    |
| `cilium`                    | Cilium 1.20.2 (CNI, kube-proxy replacement), LAN LoadBalancer IPs `192.168.11.200–230`                                        | `kube-system`               |
| `gateway-api`               | Gateway API CRDs v1.6.3 (standard channel)                                                                                    | cluster-wide                |
| `agentgateway-crds`         | agentgateway's own CRDs, v1.6.0                                                                                               | cluster-wide                |
| `agentgateway`              | agentgateway v1.6.0, the Gateway API implementation (GatewayClass `agentgateway`)                                             | `agentgateway-system`       |
| `cert-manager`              | cert-manager v1.21.2, with Gateway API support, and the Let's Encrypt ClusterIssuers                                          | `cert-manager`              |
| `external-secrets`          | External Secrets Operator 2.12.0 and the 1Password ClusterSecretStores (see [Secrets](#secrets))                              | `external-secrets`          |
| `gateways`                  | The `internal` and `public` Gateways and their certificates (see [Gateways](#gateways))                                       | `gateway`                   |
| `external-dns`              | external-dns 0.23.0 (chart 1.23.0): public DNS on Cloudflare for routes on the `public` Gateway                               | `external-dns`              |
| `tailscale-operator`        | Tailscale operator 1.102.4 and the subnet router for the tailnet                                                              | `tailscale`                 |
| `local-path-provisioner`    | local-path-provisioner v0.0.37: default StorageClass `local-path`, volumes on the Talos `local-storage` partition             | `local-path-storage`        |
| `cloudnative-pg`            | CloudNativePG operator 1.30.1 (chart 0.29.1)                                                                                  | `cnpg-system`               |
| `gpu-operator`              | NVIDIA GPU Operator v26.7.2: device plugin, `nvidia` RuntimeClass (driver and toolkit come from Talos)                        | `gpu-operator`              |
| `victoria-metrics-operator` | VictoriaMetrics operator v0.75.0 (chart 0.68.1), plus the Prometheus Operator CRDs 0.94.1 (no operator)                       | `victoria-metrics-operator` |
| `opentelemetry-operator`    | OpenTelemetry Operator 0.161.0 (chart 0.126.1)                                                                                | `opentelemetry-operator`    |
| `grafana-operator`          | Grafana Operator v5.25.0                                                                                                      | `grafana-operator`          |
| `observability`             | Storage, the collectors, Grafana 13.2.4, node-exporter (see [Observability](#observability))                                  | `observability`             |

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

Grafana's `admin` password, in `homelab-management`:

```sh
op item create --vault homelab-management --category login --title grafana-admin \
  --url https://grafana.lab.ehakan.dev --generate-password=40,letters,digits username=admin
```

Rotating a token: create a new one, update the 1Password item, delete the
`onepassword-<vault>` Secret in `external-secrets`, and recreate it with step 3
of the runbook.

### GitHub App

Argo CD reaches ehakan's GitHub repos (`homelab`, `homelab-private`,
`homelab-apps`) as the GitHub App `ehakan-homelab-argocd`, for syncing
([`configs/argocd/repo-creds.yaml`](configs/argocd/repo-creds.yaml)) and, once
set up, Source Hydrator pushes, notifications (commit statuses, check runs,
deployments, PR comments) and GitOps Promoter. Repository permissions:

| Permission      | Access         |
| --------------- | -------------- |
| Contents        | Read and write |
| Pull requests   | Read and write |
| Commit statuses | Read and write |
| Checks          | Read and write |
| Deployments     | Read and write |
| Metadata        | Read (always)  |

No account permissions. At <https://github.com/settings/apps/new>:

1. Name `ehakan-homelab-argocd`. Uncheck Webhook → Active. Set the repository
   permissions above. Where can this app be installed: Only on this account.
2. Create, note the App ID, and generate a private key (downloads a `.pem`).
3. Install App → only select repositories: the three above (add
   `homelab-apps` once it exists). The installation ID is the number at the
   end of the URL of the installation's settings page.
4. In the 1Password app, create an **SSH Key** item `argocd-github-app` in
   `homelab-management`: Add Private Key → Import a Key File → the `.pem`.
   Add two text fields, `app-id` and `installation-id`. Then delete the
   `.pem`. 1Password's SSH agent only offers keys from vaults it's configured
   for (by default Personal/Private), so this key never ends up in SSH.

Install the app on `homelab` before Argo CD picks up `repo-creds.yaml`: the
credential template covers the public repo too, and Argo CD stops syncing if
it's broken.

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

Public DNS follows the routes: external-dns gives every route attached to
`public` a CNAME to `home.lab.ehakan.dev`, the home IP (OpenTofu,
[`terraform/cloudflare`](../terraform/cloudflare)), and deletes it when the
route detaches. Private names never appear in public DNS.

Both Gateways set `X-Forwarded-Proto` and `X-Forwarded-For` on requests
([`configs/gateways/forwarded-headers.yaml`](configs/gateways/forwarded-headers.yaml)).
Apps that need the client's IP trust `X-Forwarded-For` from the pod network,
`10.244.0.0/16`. The client IP is only real while the `public` pod runs on the
node announcing `192.168.11.201` (`kubectl -n kube-system get lease
cilium-l2announce-gateway-public`); otherwise Cilium replaces it with a node
IP, which apps should not treat as LAN.

Certificates come from Let's Encrypt (`letsencrypt-production`) via DNS-01 on
Cloudflare, see
[`configs/gateways/certificates.yaml`](configs/gateways/certificates.yaml).

Outside the cluster:

- Router DNS: `*.lab.ehakan.dev` → `192.168.11.200` (manual, router config).
- Router port-forward: 443 and 80 → `192.168.11.201` (manual).
- `home.lab.ehakan.dev`, the external-dns token and the Tailscale side:
  [`terraform/`](../terraform).

## Observability

Metrics and logs in VictoriaMetrics and VictoriaLogs, collected by
OpenTelemetry collectors and shown in Grafana at
<https://grafana.lab.ehakan.dev> (`admin`, password in 1Password
`homelab-management/grafana-admin`). Everything is an operator's resource in
[`configs/observability/resources/`](configs/observability/resources), and
everything but the DaemonSets runs on `hl-tal-mini-01`, volumes on its
`local-storage` partition.

| Piece                              | Resource                                                                       | Notes                                                                                                                         |
| ---------------------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Metrics storage                    | `VMSingle` `metrics`                                                           | 30 days, 20 Gi; `http://vmsingle-metrics.observability.svc:8428` (Prometheus API, remote write, OTLP)                         |
| Log storage                        | `VLSingle` `logs`                                                              | 14 days, 20 Gi; `http://vlsingle-logs.observability.svc:9428` (LogsQL, OTLP)                                                  |
| Kubernetes objects                 | `OpenTelemetryCollector` `cluster` (`k8s_cluster`)                             | pod phases, container states and stuck reasons, restarts, replica counts, node conditions, volume claims, requests and limits |
| Node, pod and container usage      | `OpenTelemetryCollector` `node`, a DaemonSet (`kubelet_stats`, `host_metrics`) | CPU, memory, filesystems, network, volumes; the host's disks, load, paging, processes                                         |
| Temperatures, pressure, clock sync | node-exporter, a DaemonSet                                                     | only the `hwmon`, `thermal_zone`, `pressure` and `timex` collectors                                                           |
| Prometheus-format targets          | the `cluster` collector's Target Allocator                                     | every `ServiceMonitor`, `PodMonitor`, `Probe` and `ScrapeConfig` in the cluster, plus the API server; every 30 s              |
| Pod logs                           | `OpenTelemetryCollector` `node` (`file_log`)                                   | every container's stdout and stderr, from the kubelet's files; read positions in `/var/lib/otelcol` on each node              |
| Kubernetes events                  | `OpenTelemetryCollector` `cluster` (`k8s_objects`)                             | one log line per event and per repeat (`FailedScheduling`, `BackOff`, `Pulled`, ...)                                          |
| Grafana                            | `Grafana` `grafana`, `GrafanaDatasource`s                                      | no volume: the operator re-applies data sources and dashboards after a restart                                                |

Every pod's logs and metrics carry, like Datadog's `service`, `env` and
`version` tags:

| Attribute                     | From                                                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `service.name`                | the pod annotation `resource.opentelemetry.io/service.name`                                                         |
| `service.version`             | the pod's `app.kubernetes.io/version` label, else its image tag (without a digest)                                  |
| `deployment.environment.name` | `prod`, set by the collectors unless the pod sets its own (`resource.opentelemetry.io/deployment.environment.name`) |
| `k8s.cluster.name`            | `homelab`, set by the collectors                                                                                    |

Every workload sets the annotation, through its chart's values (usually
`podAnnotations`), a patch or its manifest. Names are unique in the cluster,
prefixed where the component's own name is generic (`cert-manager-webhook`,
`argocd-repo-server`, `otel-node-collector`); no `service.namespace`, the
Kubernetes namespace is enough. Without the annotation, the collector falls
back to the `app.kubernetes.io/instance` or `name` label, then the workload's
name. Set in the collectors instead (`transform/service`): Talos' static pods
(`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`) and the Target
Allocator (`otel-target-allocator`). CoreDNS (`coredns`) and the GPU
operator's own DaemonSets keep their workload names.

Two naming styles, on purpose:

- OpenTelemetry metrics (the receivers above, later apps' OTLP) keep their
  OpenTelemetry names and get their resource attributes as labels:
  `k8s.container.restarts{k8s.namespace.name="media", k8s.pod.name="..."}`.
  Pod labels are `k8s.pod.label.<key>`; label names with `/` need quotes:
  `{"k8s.pod.label.app.kubernetes.io/name"="grafana"}`.
- Prometheus-format targets keep their names and labels exactly as exposed
  (`node_hwmon_temp_celsius{job="node-exporter"}`): they go through Prometheus
  remote write.

The API server's metrics are an allowlist (`metric_relabel_configs` in
`collector-cluster.yaml`): it exposes ~95k series, almost all histogram
buckets.

Logs, in Grafana's VictoriaLogs data source (LogsQL). Streams are
`service.name`, `k8s.namespace.name`, `k8s.pod.name` and `k8s.container.name`
for pod logs, `k8s.namespace.name` for events; pod labels and everything else
are ordinary fields:

```text
{service.name="argocd-repo-server"} severity_text:=ERROR
{k8s.namespace.name="media"} timeout
{k8s.namespace.name="observability"} k8s.pod.label.app:=grafana
k8s.event.reason:FailedScheduling
exception.message:*
```

The node collector normalizes pod logs (`transform/logs` and
`transform/severity` in `collector-node.yaml`), like Datadog's remappers:

- The message is the body (`_msg`): `msg`, `message`, CLEF's `@m`, or the
  text after a known prefix. JSON's other keys become fields under their own
  names; HTTP access lines without a message get `METHOD host/path status`.
- The level is `severity_text`, one of `TRACE`, `DEBUG`, `INFO`, `WARN`,
  `ERROR`, `FATAL` (whatever the app calls them: `Information`, `WRN`, `E`,
  `notice`...), with `severity_number`. Lines without a recognizable level
  keep none (`Unspecified`).
- Errors are `exception.message` and `exception.stacktrace`; CLEF's trace
  context is the line's `trace_id` and `span_id`; PostgreSQL's database and
  error code are `db.namespace` and `db.response.status_code`.
- The time is when the container runtime got the line; the app's own
  timestamp is dropped.
- Understood: JSON (logrus, zap, slog, klog, CLEF, Envoy, CloudNativePG),
  logfmt, and the text of klog, Go's `log`, Python logging, Serilog, winston,
  consola, Redis, CoreDNS, Envoy and `(N) <time> - msg`. Other text is kept
  as written. Recognized by shape, so a new app in one of these formats needs
  nothing.
- Stack traces: indented lines, exception headers (`System.FooException:
  ...`, `ValueError: ...`) and `Traceback`/`Caused by` lines are joined to
  the line before, in every container.

Monitoring an app: turn on its chart's `ServiceMonitor` (or write one). The
Prometheus Operator's CRDs are installed with the VictoriaMetrics operator
(`victoria-metrics-operator` app), without the Prometheus Operator itself. The
VictoriaMetrics operator only converts `PrometheusRule`s (into `VMRule`s, for
alerting); scraping is the collector's.

The collectors use the `otelcol-contrib` image, the only one with the
Prometheus remote-write exporter. If they get too heavy, VictoriaMetrics' own
agents (vmagent, vlagent) can replace them.

Not set up yet: dashboards, traces (VictoriaTraces, `VTSingle`, shown through
Grafana's Tempo data source), alerting (`VMAlert`, `VMAlertmanager`,
`VMRule`s), etcd, scheduler and controller-manager metrics (Talos binds them
to localhost), Talos' own service logs (`machine.logging`).

## Not set up yet

- **AppProjects.** Everything uses the built-in `default` project.
