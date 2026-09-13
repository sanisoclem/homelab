output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}

output "pgadmin_admin_password" {
  value     = random_password.pgadmin_admin.result
  sensitive = true
}

output "zitadel_admin_password" {
  value     = random_password.zitadel_admin.result
  sensitive = true
}
