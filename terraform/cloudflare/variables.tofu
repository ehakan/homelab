variable "state_passphrase" {
  description = "State encryption passphrase, from op://homelab-bootstrap/opentofu-state-passphrase (see terraform/op.env)."
  type        = string
  sensitive   = true
}

variable "public_ipv4" {
  description = "Home static public IPv4. The public Gateway is port-forwarded behind it. Unset: no public wildcard record."
  type        = string
  default     = null
}
