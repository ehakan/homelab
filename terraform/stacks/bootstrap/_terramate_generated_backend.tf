// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

terraform {
  backend "s3" {
    bucket         = "ehakan-homelab-tf-state"
    dynamodb_table = "ehakan-homelab-tf-state-lock"
    encrypt        = true
    key            = "terraform/stacks/by-id/86e35704-efbb-43b5-ab11-eb02fa2a5387/terraform.tfstate"
    region         = "eu-west-1"
  }
}
