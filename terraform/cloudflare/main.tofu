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

# The home IP, under one name. Public services get a CNAME to it from
# external-dns (cluster/configs/external-dns), so only names routed through the
# public Gateway exist in public DNS. At home and over Tailscale the router's
# own *.lab.ehakan.dev record wins.
data "onepassword_item" "home_public_ipv4" {
  vault = data.onepassword_vault.bootstrap.uuid
  title = "home-public-ipv4"
}

resource "cloudflare_dns_record" "home" {
  zone_id = local.zone_id
  name    = "home.lab.ehakan.dev"
  type    = "A"
  content = trimspace(data.onepassword_item.home_public_ipv4.note_value)
  ttl     = 1 # automatic
  proxied = false
  comment = "Managed by OpenTofu (terraform/cloudflare)"
}

# Tokens for in-cluster controllers: Zone Read and DNS Write on ehakan.dev.
data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = local.account_id
  name       = "DNS Write"
}

data "cloudflare_account_api_token_permission_groups_list" "zone_read" {
  account_id = local.account_id
  name       = "Zone Read"
}

locals {
  dns_edit_policies = [{
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

# cert-manager: DNS-01 challenges.
resource "cloudflare_account_token" "cert_manager" {
  account_id = local.account_id
  name       = "cert-manager (homelab)"
  policies   = local.dns_edit_policies
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

# external-dns: CNAMEs for public services.
resource "cloudflare_account_token" "external_dns" {
  account_id = local.account_id
  name       = "external-dns (homelab)"
  policies   = local.dns_edit_policies
}

# Read by External Secrets as `cloudflare-external-dns/password`.
resource "onepassword_item" "external_dns" {
  vault    = data.onepassword_vault.management.uuid
  title    = "cloudflare-external-dns"
  category = "password"
  tags     = ["opentofu"]

  password_wo         = cloudflare_account_token.external_dns.value
  password_wo_version = parseint(substr(sha1(cloudflare_account_token.external_dns.id), 0, 8), 16)
}
