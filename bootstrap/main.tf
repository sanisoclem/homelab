data "terraform_remote_state" "cluster" {
  backend = "local"

  config = {
    path = "${path.module}/../cluster/terraform.tfstate"
  }
}

module "bootstrap" {
  source = "../modules/cluster-bootstrap"

  kubeconfig_path      = var.kubeconfig_path
  egress_nodes         = data.terraform_remote_state.cluster.outputs.egress_nodes
  argocd_chart_version = var.argocd_chart_version

  gitops_repos = {
    platform = var.platform_repo_url
    hempire  = var.hempire_repo_url
    home     = var.home_repo_url
  }

  gitops_tokens = {
    platform = var.platform_token
    hempire  = var.hempire_token
    home     = var.home_token
  }

  platform_repo = "platform"
  platform_path = var.platform_path

  github_user = var.github_user
  ghcr_token  = var.ghcr_token

  sso_client_id                = var.sso_client_id
  sso_client_secret            = var.sso_client_secret
  cloudflare_api_token         = var.cloudflare_api_token
  cloudflare_hempire_api_token = var.cloudflare_hempire_api_token
  zitadel_masterkey            = var.zitadel_masterkey

  nas = {
    host         = var.nas_host
    dataset      = var.nas_dataset
    iscsi_portal = var.nas_iscsi_portal
  }

  truenas_api_key = var.truenas_api_key
  s3_access_key   = var.s3_access_key
  s3_secret_key   = var.s3_secret_key

  renovate_token      = var.renovate_token
  plex_claim_token    = var.plex_claim_token
  immichframe_api_key = var.immichframe_api_key

  app_secrets = {
    CRM_ZITADEL_CLIENT_SECRET = var.crm_zitadel_client_secret
    BFF_SESSION_SECRET        = var.bff_session_secret
    ADMIN_SESSION_SECRET      = var.admin_session_secret
    BANK_BASIQ_API_KEY        = var.bank_basiq_api_key
    BANK_CLIENT_ID            = var.bank_client_id
    BANK_CLIENT_SECRET        = var.bank_client_secret
    BRIDGE_CLIENT_ID          = var.bridge_client_id
    BRIDGE_CLIENT_SECRET      = var.bridge_client_secret
    BUDGET_CLIENT_ID          = var.budget_client_id
    BUDGET_CLIENT_SECRET      = var.budget_client_secret
  }
}
