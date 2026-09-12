output "node_ips" {
  value = module.cluster.node_ips
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "schematic_id" {
  value = module.cluster.schematic_id
}

output "gateway_ip" {
  value = var.gateway_ip
}

output "metallb_pool" {
  value = var.metallb_pool
}

output "dns_zone" {
  value = "${var.cluster_subdomain}.${var.parent_domain}"
}

output "letsencrypt_email" {
  value = var.letsencrypt_email
}

output "nas_host" {
  value = var.nas_host
}

output "nas_dataset" {
  value = var.nas_dataset
}

output "nas_iscsi_portal" {
  value = var.nas_iscsi_portal
}

output "s3_endpoint" {
  value = var.s3_endpoint
}

output "kubeconfig_path" {
  value = local_sensitive_file.kubeconfig.filename
}

output "talosconfig_path" {
  value = local_sensitive_file.talosconfig.filename
}
