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

  controlplane_vcpu      = var.controlplane_vcpu
  controlplane_memory_mb = var.controlplane_memory_mb
  worker_vcpu            = var.worker_vcpu
  worker_memory_mb       = var.worker_memory_mb
  disk_gb                = var.disk_gb

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

data "cloudflare_zone" "parent" {
  filter = {
    name = var.parent_domain
  }
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = data.cloudflare_zone.parent.zone_id
  name    = "*.${var.cluster_subdomain}.${var.parent_domain}"
  type    = "A"
  content = var.gateway_ip
  ttl     = 300
  proxied = false
}
