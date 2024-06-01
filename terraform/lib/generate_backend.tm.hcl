generate_hcl "_terramate_generated_backend.tf" {
  content {
    terraform {
      backend "s3" {
        region         = "eu-west-1"
        bucket         = "ehakan-homelab-tf-state"
        key            = "terraform/stacks/by-id/${terramate.stack.id}/terraform.tfstate"
        encrypt        = true
        dynamodb_table = "ehakan-homelab-tf-state-lock"
      }
    }
  }
}
