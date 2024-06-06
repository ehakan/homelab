// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

data "onepassword_item" "cloudflare_api_token" {
  title = "/cloudflare/api-token/ehakan-homelab-terraform"
  vault = data.onepassword_vault.homelab.uuid
}
provider "cloudflare" {
  api_token = data.onepassword_item.cloudflare_api_token.password
}
