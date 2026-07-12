# Bootstrapping note: this bucket doesn't exist until `main.tofu` has been
# applied once. First-time setup:
#   1. Temporarily comment out this whole `backend "s3"` block (leaving no
#      backend block = local backend).
#   2. tofu init && tofu apply   # creates the bucket
#   3. Uncomment this block.
#   4. tofu init -migrate-state  # copies local state into the new bucket
terraform {
  backend "s3" {
    bucket       = "ehakan-homelab-tfstate"
    key          = "bootstrap/tfstate/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
