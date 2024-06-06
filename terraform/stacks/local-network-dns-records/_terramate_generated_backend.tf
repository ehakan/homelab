// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

terraform {
  backend "s3" {
    bucket         = "ehakan-homelab-tf-state"
    dynamodb_table = "ehakan-homelab-tf-state-lock"
    encrypt        = true
    key            = "terraform/stacks/by-id/a2f02025-bd7d-4f13-9ae2-dfb7d6d9a0ed/terraform.tfstate"
    region         = "eu-west-1"
  }
}
