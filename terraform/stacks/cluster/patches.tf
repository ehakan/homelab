locals {
  patches = {
    workloadsOnControlPlane = yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    })
    disableDefaultCni = yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  }
}
