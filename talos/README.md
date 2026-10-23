# Talos Linux

Machine configs for the `homelab` cluster, generated from:

| Path | Contents |
|---|---|
| [`secrets.sops.yaml`](secrets.sops.yaml) | Cluster secrets bundle, sops-encrypted (see [Secrets](#secrets)) |
| [`patches/common.yaml`](patches/common.yaml) | All nodes: no Flannel, no kube-proxy (Cilium replaces both) |
| [`patches/controlplane.yaml`](patches/controlplane.yaml) | Control plane: cert SANs, workloads allowed, JSON logs from the control plane components |
| [`nodes/`](nodes) | Per node: hostname, install disk, installer image, disk layout |
| [`schematics/`](schematics) | Image Factory schematics (installer/ISO images) |
| `generated/` | **Gitignored.** Rendered configs, `talosconfig`, `kubeconfig` |

Kubernetes resources (Cilium included) are not part of the Talos config. They
are managed by Argo CD.

## Node Information

| Node | Hardware | Role | Address | Install disk | Secure Boot | Disk encryption |
|---|---|---|---|---|---|---|
| `hl-tal-mini-01` | AZW GK35 mini-PC, 8GB | control plane (schedulable) | `192.168.11.10` (`kube.lan.ehakan.dev`) | 256GB SATA SSD, `/dev/disk/by-id/ata-SSD_256GB_2021091400158`: EPHEMERAL 80GiB, rest `local-storage` (PersistentVolumes) | yes | none (no TPM) |
| `hl-tal-tower-01` | desktop (MSI MS-7C31, i5-9400F), 16GB, GTX 1050 Ti | worker (media, NVIDIA 580 driver) | `192.168.11.11` | 480GB SATA SSD, `/dev/disk/by-id/ata-CT480BX500SSD1_2229E649CC02`: EPHEMERAL 80GiB, rest `local-storage` | no | none (no TPM) |
| `hl-tal-tower-02` | desktop, 64GB, RTX 5080 | worker | not set up yet | | yes | |

Node addresses are DHCP reservations on the router, not static config in Talos.

## Prerequisites

Run everything from the repo root with mise activated. That provides the
pinned `talosctl` and sets:

- `TALOSCONFIG`, `KUBECONFIG`: point into `talos/generated/`
- `SOPS_AGE_SSH_PRIVATE_KEY_CMD`: reads the sops key from 1Password
  (`op://homelab-bootstrap/sops-talos`), so `op` must be signed in

## Runbook

### 1. Generate configs

Renders the base configs and `talosconfig` into `talos/generated/`.
`sops exec-file` hands talosctl a temporary decrypted copy of the secrets and
deletes it afterwards.

```sh
sops exec-file --no-fifo talos/secrets.sops.yaml 'talosctl gen config homelab https://kube.lan.ehakan.dev:6443 \
  --with-secrets {} \
  --kubernetes-version 1.37.1 \
  --with-docs=false --with-examples=false \
  --config-patch @talos/patches/common.yaml \
  --config-patch-control-plane @talos/patches/controlplane.yaml \
  --output talos/generated --force'
```

Point `talosconfig` at the control plane:

```sh
talosctl config endpoint kube.lan.ehakan.dev
talosctl config node kube.lan.ehakan.dev
```

Re-run this step after any change to `patches/` or the Talos or Kubernetes
version. Node patches (`nodes/`) aren't baked in here: every `apply-config`
adds the node's patch with `--config-patch`. Always pass it, or the node's
hostname, installer image and install disk revert to defaults.

### 2. Install a node (from maintenance mode)

Boot the node from its schematic's ISO (see [`schematics/`](schematics)), then
apply the role's config plus the node's patch. Control plane:

```sh
talosctl apply-config --insecure --nodes 192.168.11.10 \
  --file talos/generated/controlplane.yaml \
  --config-patch @talos/nodes/controlplane.yaml
```

Worker, e.g. `hl-tal-tower-01`:

```sh
talosctl apply-config --insecure --nodes 192.168.11.11 \
  --file talos/generated/worker.yaml \
  --config-patch @talos/nodes/hl-tal-tower-01.yaml
```

Talos wipes the selected disk, installs and reboots; this takes several
minutes. Remove the USB stick once it
starts rebooting, or it boots back into maintenance mode.

### 3. Bootstrap the cluster (once, first control plane only)

```sh
talosctl bootstrap
```

Wait until etcd and the Kubernetes control plane are up (`talosctl dashboard`,
or `talosctl service etcd`). `talosctl health` won't pass yet: nodes stay
`NotReady` until a CNI is installed.

### 4. Fetch kubeconfig

```sh
talosctl kubeconfig --merge=false --force $KUBECONFIG
kubectl get nodes   # NotReady until Cilium is installed
```

Then continue with the Kubernetes bootstrap (Cilium, Argo CD).

### Changing config on a running node

Regenerate (step 1) if `patches/` changed, then preview and apply:

```sh
talosctl apply-config --nodes kube.lan.ehakan.dev \
  --file talos/generated/controlplane.yaml \
  --config-patch @talos/nodes/controlplane.yaml \
  --dry-run
```

For a worker, use its address, `talos/generated/worker.yaml` and its node
patch instead. Re-run without `--dry-run` to apply. Don't use `talosctl patch machineconfig`
or `talosctl edit`: those change only the node and drift from the repo.

### Upgrading Talos

Bump `talosctl` in `mise.toml`, update the version in the node's installer
image in `nodes/`, regenerate (step 1), apply the config (see above), then:

```sh
talosctl upgrade --nodes kube.lan.ehakan.dev \
  --image factory.talos.dev/metal-installer-secureboot/<schematic-id>:<version>
```

Extensions only change through an upgrade, so the same applies after editing a
schematic.

### Repartitioning

Volume sizes (`VolumeConfig`, `UserVolumeConfig` in `nodes/`) only apply when
a volume is created. To resize EPHEMERAL, wipe it: `talosctl reset` drops the
partition, and on the next boot Talos re-creates it, and any user volumes in
the freed space, from the config. No reinstall. etcd lives on EPHEMERAL, so on
the single control plane this wipes the cluster, which is then rebuilt from
git.

1. Push the config changes. Remove the node's Tailscale devices
   (`homelab-k8s-operator`, `homelab-subnet-router`) in the admin console, so
   the rebuilt ones get the same names.
2. Apply the new config (see Changing config on a running node), then wipe
   EPHEMERAL and reboot:

   ```sh
   talosctl reset --system-labels-to-wipe EPHEMERAL --graceful=false --reboot
   ```

3. Continue with steps 3–4 of the runbook (bootstrap, kubeconfig), then check
   the layout:

   ```sh
   talosctl get volumestatus EPHEMERAL u-local-storage
   ```

4. Bootstrap Kubernetes again: [`cluster/README.md`](../cluster/README.md).

## Secrets

`secrets.sops.yaml` holds the cluster's CAs, tokens and encryption keys. It
was generated once and must never be regenerated: a new bundle is a new
cluster identity. It's encrypted to the `sops-talos` SSH key in the 1Password
vault `homelab-bootstrap`. A backup copy of the encrypted file is in the same
vault as the Document `talos-secrets`. If this file changes, re-upload it:

```sh
op document edit talos-secrets talos/secrets.sops.yaml --vault homelab-bootstrap
```

Decrypted secrets only ever exist transiently (`sops exec-file`) or inside the
gitignored `generated/`.
