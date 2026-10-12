terraform {
  required_version = ">= 1.13.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.27.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.3.1"
    }
  }
}
