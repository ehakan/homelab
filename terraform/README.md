# OpenTofu

Everything on Cloudflare and Tailscale that no in-cluster controller manages
(cert-manager, the Tailscale operator) is managed here.

| Module | Manages |
|---|---|
| [`cloudflare/`](cloudflare) | Public DNS `*.lab.ehakan.dev` → home IP; cert-manager's API token |
| [`tailscale/`](tailscale) | Tailnet policy (tags, subnet route approval, access), split DNS for `lab.ehakan.dev`, the operator's OAuth client |

Credentials the modules generate (cert-manager's token, the operator's OAuth
client) are written straight into the 1Password vault `homelab-management`
for External Secrets, with write-only attributes. They also stay in each
module's state, as the creating resources have no write-only variant, so
state is encrypted (passphrase in `homelab-bootstrap`). State lives in the
`ehakan-homelab-tfstate` bucket ([`bootstrap/tfstate`](../bootstrap/tfstate)).

## One-time setup

In the 1Password vault `homelab-bootstrap`:

| Item                        | Category       | Contents                                                                                                                                                                                         |
| --------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `opentofu-state-passphrase` | Password       | 32+ random characters. Losing it makes the state unreadable.                                                                                                                                     |
| `cloudflare-opentofu`       | API Credential | `credential`: a Cloudflare account API token with two policies: account → Account API Tokens: Edit; zone `ehakan.dev` → Zone: Read, DNS: Edit                                                    |
| `tailscale-opentofu`        | API Credential | `username`: OAuth client ID, `credential`: client secret. A Tailscale trust credential with write on Policy File, DNS, Services, Devices Core, Auth Keys, OAuth Keys, and tag `tag:k8s-operator` |

```sh
op item create --vault homelab-bootstrap --category password \
  --title opentofu-state-passphrase --generate-password=64,letters,digits
```

The modules sign in to 1Password through the desktop app. Put your account
name or ID in `mise.local.toml` (gitignored):

```toml
[env]
OP_ACCOUNT = "<account name or ID, see `op account list`>"
```

`cloudflare/` creates the public `*.lab.ehakan.dev` record only once
`public_ipv4` is set in `cloudflare/terraform.tfvars`.

## Running

From the repo root, with AWS credentials for the state bucket (see
[`bootstrap/tfstate`](../bootstrap/tfstate/README.md)):

```sh
op run --env-file terraform/op.env -- tofu -chdir=terraform/<module> init
op run --env-file terraform/op.env -- tofu -chdir=terraform/<module> plan
op run --env-file terraform/op.env -- tofu -chdir=terraform/<module> apply
```

`op run` only injects the state passphrase; provider credentials are read by
the modules themselves, as ephemeral values that never reach state.

A credential can only create OAuth clients with scopes and tags it has
itself, hence the operator's scopes on `tailscale-opentofu`. `tag:k8s-operator`
only exists after the first apply of the policy: on a fresh tailnet, apply with
`-target=tailscale_acl.policy` first, then add the operator scopes and tag.

Apply `tailscale/` before installing the Tailscale operator, and `cloudflare/`
before cert-manager's issuers: both read their credentials from 1Password.

New module: `terraform/<name>/`, same file layout, backend `key`
`terraform/<name>/terraform.tfstate`, and the same `encryption` block if
its state holds secrets.
