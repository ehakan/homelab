# Signs in through the 1Password desktop app; set OP_ACCOUNT (see
# terraform/README.md).
provider "onepassword" {}

provider "cloudflare" {
  api_token = ephemeral.onepassword_item.cloudflare_opentofu.credential
}
