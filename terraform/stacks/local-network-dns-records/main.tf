data "cloudflare_zone" "this" {
  name = "ehakan.dev"
}

resource "cloudflare_record" "cluster_internal" {
  zone_id = data.cloudflare_zone.this.id
  name    = "kube.cluster.int.homelab"
  type    = "A"
  value   = "192.168.1.150"
}
