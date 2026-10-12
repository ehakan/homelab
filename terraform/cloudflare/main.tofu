data "onepassword_vault" "bootstrap" {
  name = "homelab-bootstrap"
}

data "onepassword_vault" "management" {
  name = "homelab-management"
}

# Token OpenTofu itself runs with. Created by hand; never stored in state.
ephemeral "onepassword_item" "cloudflare_opentofu" {
  vault = data.onepassword_vault.bootstrap.uuid
  title = "cloudflare-opentofu"
}

data "cloudflare_zone" "ehakan_dev" {
  filter = {
    name = "ehakan.dev"
  }
}

locals {
  zone_id    = data.cloudflare_zone.ehakan_dev.zone_id
  account_id = data.cloudflare_zone.ehakan_dev.account.id
}

# Every homelab hostname resolves publicly to the home IP, where only the
# public Gateway answers. Private names get a 404 there; at home and over
# Tailscale the router's own *.lab.ehakan.dev record wins. A wildcard keeps
# the list of services out of public DNS.
resource "cloudflare_dns_record" "lab_wildcard" {
  count = var.public_ipv4 == null ? 0 : 1

  zone_id = local.zone_id
  name    = "*.lab.ehakan.dev"
  type    = "A"
  content = var.public_ipv4
  ttl     = 1 # automatic
  proxied = false
  comment = "Managed by OpenTofu (terraform/cloudflare)"
}

# cert-manager: DNS-01 challenges for ehakan.dev.
data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = local.account_id
  name       = "DNS Write"
}

data "cloudflare_account_api_token_permission_groups_list" "zone_read" {
  account_id = local.account_id
  name       = "Zone Read"
}

resource "cloudflare_account_token" "cert_manager" {
  account_id = local.account_id
  name       = "cert-manager (homelab)"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = data.cloudflare_account_api_token_permission_groups_list.dns_write.result[0].id },
      { id = data.cloudflare_account_api_token_permission_groups_list.zone_read.result[0].id },
    ]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${local.zone_id}" = "*"
    })
  }]
}

# Read by External Secrets as `cloudflare-cert-manager/password`.
resource "onepassword_item" "cert_manager" {
  vault    = data.onepassword_vault.management.uuid
  title    = "cloudflare-cert-manager"
  category = "password"
  tags     = ["opentofu"]

  password_wo = cloudflare_account_token.cert_manager.value
  # Write-only values are only sent when this changes: re-send whenever the
  # token is replaced.
  password_wo_version = parseint(substr(sha1(cloudflare_account_token.cert_manager.id), 0, 8), 16)
}
