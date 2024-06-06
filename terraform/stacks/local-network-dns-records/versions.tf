terraform {
  required_version = "~> 1.6"
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.0.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.34.0"
    }
  }
}
