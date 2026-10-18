# Manifests that shouldn't be public, next to this repo.
resource "github_repository" "homelab_private" {
  name        = "homelab-private"
  description = "Private half of ehakan/homelab"
  visibility  = "private"

  # Creates `main` with an empty commit, so the repo can be cloned and
  # pointed at right away.
  auto_init = true

  has_issues   = false
  has_projects = false
  has_wiki     = false

  # A destroy archives the repo instead of deleting it.
  archive_on_destroy = true
}
