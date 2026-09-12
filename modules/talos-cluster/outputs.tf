output "node_ips" {
  value = local.ips
}

output "cluster_endpoint" {
  value = local.endpoint
}

output "kubeconfig_raw" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "talosconfig_raw" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "schematic_id" {
  value       = talos_image_factory_schematic.this.id
  description = "Image Factory schematic the nodes boot and upgrade from"
}
