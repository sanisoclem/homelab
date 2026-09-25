output "grafana_admin_password" {
  value     = var.stable_secrets.grafana_admin_password
  sensitive = true
}

output "pgadmin_admin_password" {
  value     = var.stable_secrets.pgadmin_admin_password
  sensitive = true
}

output "zitadel_admin_password" {
  value     = var.stable_secrets.zitadel_admin_password
  sensitive = true
}
