output "grafana_admin_password" {
  value     = module.bootstrap.grafana_admin_password
  sensitive = true
}

output "zitadel_admin_password" {
  value     = module.bootstrap.zitadel_admin_password
  sensitive = true
}
