variable "state_passphrase" {
  description = "State encryption passphrase, from op://homelab-bootstrap/opentofu-state-passphrase (see terraform/op.env)."
  type        = string
  sensitive   = true
}
