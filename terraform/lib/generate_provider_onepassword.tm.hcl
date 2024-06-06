generate_hcl "_terramate_generated_provider_onepassword.tf" {
  content {
    provider "onepassword" {
      account = "FSPRZ7UCGJCZDBBVPNLNTBINXQ"
    }

    data "onepassword_vault" "homelab" {
      name = "homelab"
    }
  }
}
