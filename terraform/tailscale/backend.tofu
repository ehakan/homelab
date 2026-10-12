terraform {
  backend "s3" {
    bucket       = "ehakan-homelab-tfstate"
    key          = "terraform/tailscale/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  # State holds the generated operator OAuth client secret
  # (tailscale_oauth_client has no write-only/ephemeral variant), so it's
  # encrypted client-side.
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
