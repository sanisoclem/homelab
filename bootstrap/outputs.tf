output "grafana_admin_password" {
  value     = module.bootstrap.grafana_admin_password
  sensitive = true
}

output "pgadmin_admin_password" {
  value     = module.bootstrap.pgadmin_admin_password
  sensitive = true
}

output "zitadel_admin_password" {
  value     = module.bootstrap.zitadel_admin_password
  sensitive = true
}
