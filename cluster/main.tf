module "cluster" {
  source = "../modules/talos-cluster"

  cluster_name       = var.cluster_name
  proxmox_node       = var.proxmox_node
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  controlplane_ips = var.controlplane_ips
  worker_ips       = var.worker_ips
  controlplane_vip = var.controlplane_vip
  gateway          = var.node_gateway
  nameservers      = var.nameservers
  bridge           = var.bridge
  vlan_id          = var.vlan_id
  egress_vlan_id   = var.egress_vlan_id
  egress_gateway   = var.egress_gateway
  egress_workers   = var.egress_workers

  controlplane_vcpu       = var.controlplane_vcpu
  controlplane_memory_mb  = var.controlplane_memory_mb
  worker_vcpu             = var.worker_vcpu
  worker_memory_mb        = var.worker_memory_mb
  egress_worker_vcpu      = var.egress_worker_vcpu
  egress_worker_memory_mb = var.egress_worker_memory_mb
  disk_gb                 = var.disk_gb

  vm_datastore_id      = var.vm_datastore_id
  image_datastore_id   = var.image_datastore_id
  snippet_datastore_id = var.snippet_datastore_id
  vm_id_base           = var.vm_id_base
  startup_order        = var.startup_order

  dockerhub_username = var.dockerhub_username
  dockerhub_token    = var.dockerhub_token
}

resource "local_sensitive_file" "kubeconfig" {
  filename        = pathexpand(var.kubeconfig_path)
  content         = module.cluster.kubeconfig_raw
  file_permission = "0600"
}

resource "local_sensitive_file" "talosconfig" {
  filename        = pathexpand(var.talosconfig_path)
  content         = module.cluster.talosconfig_raw
  file_permission = "0600"
}

locals {
  dns_zone     = var.cluster_subdomain == "" ? var.parent_domain : "${var.cluster_subdomain}.${var.parent_domain}"
  hempire_zone = var.hempire_subdomain == "" ? var.hempire_domain : "${var.hempire_subdomain}.${var.hempire_domain}"
}

data "cloudflare_zone" "parent" {
  filter = {
    name = var.parent_domain
  }
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = data.cloudflare_zone.parent.zone_id
  name    = "*.${local.dns_zone}"
  type    = "A"
  content = var.gateway_ip
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "home_wildcard" {
  zone_id = data.cloudflare_zone.parent.zone_id
  name    = "*.${var.home_subdomain}.${local.dns_zone}"
  type    = "A"
  content = var.home_gateway_ip
  ttl     = 300
  proxied = false
}

data "cloudflare_zone" "hempire" {
  count    = var.hempire_domain == "" ? 0 : 1
  provider = cloudflare.hempire

  filter = {
    name = var.hempire_domain
  }
}

resource "cloudflare_dns_record" "hempire_wildcard" {
  count    = var.hempire_domain == "" ? 0 : 1
  provider = cloudflare.hempire

  zone_id = data.cloudflare_zone.hempire[0].zone_id
  name    = "*.${local.hempire_zone}"
  type    = "A"
  content = var.gateway_ip
  ttl     = 300
  proxied = false
}
