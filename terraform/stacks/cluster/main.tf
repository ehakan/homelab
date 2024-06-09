resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = "192.168.1.150"
  config_patches = [
    local.patches.workloadsOnControlPlane,
    local.patches.disableDefaultCni,
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sdb"
        }
        network = {
          hostname = "homelab-cluster-controlplane-01"
        }
      }
    }),
  ]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = "192.168.1.150"

  depends_on = [talos_machine_configuration_apply.controlplane]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = ["192.168.1.150"]
}

data "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = "192.168.1.150"

  depends_on = [talos_machine_configuration_apply.controlplane]
}
