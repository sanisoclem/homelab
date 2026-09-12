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

output "egress_nodes" {
  value       = [for name, node in local.nodes : name if node.egress != null]
  description = "Workers with an interface on the egress VLAN. Their label and taint are applied by the bootstrap root, because NodeRestriction forbids a worker setting either on itself"
}
