generate_hcl "_terramate_generated_provider_cloudflare.tf" {
  content {
    data "onepassword_item" "cloudflare_api_token" {
      vault = data.onepassword_vault.homelab.uuid
      title = "/cloudflare/api-token/ehakan-homelab-terraform"
    }

    provider "cloudflare" {
      api_token = data.onepassword_item.cloudflare_api_token.password
    }
  }
}
