stack {
  name        = "local-network-dns-records"
  description = "local-network-dns-records"
  id          = "a2f02025-bd7d-4f13-9ae2-dfb7d6d9a0ed"
}

import {
  # import a specific file
  source = "/terraform/lib/generate_provider_onepassword.tm.hcl"
}

import {
  # import a specific file
  source = "/terraform/lib/generate_provider_cloudflare_via_onepassword.tm.hcl"
}
