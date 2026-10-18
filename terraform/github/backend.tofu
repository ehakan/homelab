terraform {
  backend "s3" {
    bucket       = "ehakan-homelab-tfstate"
    key          = "terraform/github/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
