# bootstrap/tfstate

Isolated root module that creates the S3 bucket used as the OpenTofu state
backend for this whole repo (`ehakan-homelab-tfstate`), then hosts its own
state in that same bucket.

## Bootstrapping

This is a chicken-and-egg setup: the bucket that will store state doesn't
exist until this module is first applied, so it starts out on a local
backend and then migrates itself into S3.

```sh
export AWS_PROFILE=/aws/sso/ehakan/homelab/admin  # or your own profile
cd bootstrap/tfstate

# 1. backend.tofu's `backend "s3"` block starts commented out (local backend).
tofu init
tofu apply

# 2. Uncomment the `backend "s3"` block in backend.tofu, then:
tofu init -migrate-state   # answer "yes" to copy local state into the bucket

# 3. Confirm the migration:
tofu plan   # should report no changes
```

Once migrated, the local `terraform.tfstate` / `terraform.tfstate.backup`
files are redundant (and gitignored) — safe to delete.

## Bucket configuration

- Versioning enabled, for state recovery.
- Server-side encryption (SSE-S3/AES256) enforced by default.
- All public access blocked, ACLs disabled (`BucketOwnerEnforced`).
- Locking uses OpenTofu's native S3 locking (`use_lockfile = true`, backed by
  conditional writes) — no DynamoDB table.

## Convention for future root modules

Every other root module in this repo should back its state onto this same
bucket, with the S3 backend `key` set to its path relative to the repo root:

```hcl
terraform {
  backend "s3" {
    bucket       = "ehakan-homelab-tfstate"
    key          = "<path/from/repo/root>/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```
