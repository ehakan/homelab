data "onepassword_vault" "bootstrap" {
  name = "homelab-bootstrap"
}

data "onepassword_vault" "management" {
  name = "homelab-management"
}

# Trust credential OpenTofu itself runs with. Created by hand; never stored
# in state.
ephemeral "onepassword_item" "tailscale_opentofu" {
  vault = data.onepassword_vault.bootstrap.uuid
  title = "tailscale-opentofu"
}

locals {
  router          = "192.168.10.1/32"
  gateway_private = "192.168.11.200/32" # Gateway `internal`, see cluster/configs/cilium
}

# The whole tailnet policy file. Use tags, never personal addresses: this
# repo is public.
resource "tailscale_acl" "policy" {
  overwrite_existing_content = true

  acl = jsonencode({
    tagOwners = {
      "tag:k8s-operator"      = ["autogroup:admin"]
      "tag:k8s"               = ["tag:k8s-operator"]
      "tag:k8s-subnet-router" = ["tag:k8s-operator"]
    }

    # The operator's subnet router (a `Connector`) advertises the private
    # Gateway and the router's DNS. Only that tag may.
    autoApprovers = {
      routes = {
        (local.gateway_private) = ["tag:k8s-subnet-router"]
        (local.router)          = ["tag:k8s-subnet-router"]
      }
    }

    grants = [
      # Your own devices can reach each other.
      { src = ["autogroup:member"], dst = ["autogroup:self"], ip = ["*"] },
      # Private services through the internal Gateway.
      { src = ["autogroup:member"], dst = [local.gateway_private], ip = ["tcp:80", "tcp:443"] },
      # Split DNS for lab.ehakan.dev goes to the router.
      { src = ["autogroup:member"], dst = [local.router], ip = ["tcp:53", "udp:53"] },
    ]

    ssh = [{
      action = "check"
      src    = ["autogroup:member"]
      dst    = ["autogroup:self"]
      users  = ["autogroup:nonroot", "root"]
    }]
  })
}

# Tailnet devices resolve *.lab.ehakan.dev with the router, like the LAN does,
# so every name maps to the same LAN IP everywhere.
resource "tailscale_dns_split_nameservers" "lab" {
  domain      = "lab.ehakan.dev"
  nameservers = [trimsuffix(local.router, "/32")]
}

# Credentials for the Kubernetes operator.
resource "tailscale_oauth_client" "k8s_operator" {
  description = "homelab k8s operator"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s-operator"]

  # The tag must exist in the policy first.
  depends_on = [tailscale_acl.policy]
}

# Read by External Secrets as `tailscale-operator/username` (client ID) and
# `tailscale-operator/password` (client secret).
resource "onepassword_item" "k8s_operator" {
  vault    = data.onepassword_vault.management.uuid
  title    = "tailscale-operator"
  category = "login"
  tags     = ["opentofu"]

  username    = tailscale_oauth_client.k8s_operator.id
  password_wo = tailscale_oauth_client.k8s_operator.key
  # Write-only values are only sent when this changes: re-send whenever the
  # client is replaced.
  password_wo_version = parseint(substr(sha1(tailscale_oauth_client.k8s_operator.id), 0, 8), 16)
}
