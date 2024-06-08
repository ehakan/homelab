// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

terraform {
  backend "s3" {
    bucket         = "ehakan-homelab-tf-state"
    dynamodb_table = "ehakan-homelab-tf-state-lock"
    encrypt        = true
    key            = "terraform/stacks/by-id/8a0bc4ae-59f1-41d6-8b9a-fb7e7278e62e/terraform.tfstate"
    region         = "eu-west-1"
  }
}
