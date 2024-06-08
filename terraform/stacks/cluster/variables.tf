variable "cluster_name" {
  type    = string
  default = "homelab"
}

variable "cluster_endpoint" {
  type    = string
  default = "https://kube.cluster.int.homelab.ehakan.dev:6443"
}
