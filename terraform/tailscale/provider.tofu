# Signs in through the 1Password desktop app; set OP_ACCOUNT (see
# terraform/README.md).
provider "onepassword" {}

provider "tailscale" {
  oauth_client_id     = ephemeral.onepassword_item.tailscale_opentofu.username
  oauth_client_secret = ephemeral.onepassword_item.tailscale_opentofu.credential
}
