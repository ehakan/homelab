terraform {
  backend "s3" {
    bucket       = "ehakan-homelab-tfstate"
    key          = "terraform/cloudflare/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  # State holds the generated cert-manager token (cloudflare_account_token
  # has no write-only/ephemeral variant), so it's encrypted client-side.
  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "passphrase" {
      keys = key_provider.pbkdf2.passphrase
    }
    state {
      method   = method.aes_gcm.passphrase
      enforced = true
    }
    plan {
      method   = method.aes_gcm.passphrase
      enforced = true
    }
  }
}
