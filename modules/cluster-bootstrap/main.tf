locals {
  registry_dockerconfig = jsonencode({
    auths = {
      (var.registry_host) = {
        auth = base64encode("puller:${var.registry_puller_password}")
      }
    }
  })
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace" "secrets" {
  metadata {
    name = "secrets"
  }
}

resource "kubernetes_secret" "hempire_db" {
  metadata {
    name      = "hempire-db"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    username = "hempire"
    password = var.stable_secrets.hempire_db_password
  }
}

resource "kubernetes_secret" "argocd_oidc" {
  metadata {
    name      = "argocd-oidc"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    clientId     = var.sso_client_id
    clientSecret = var.sso_client_secret
  }
}

resource "kubernetes_secret" "grafana_oidc" {
  metadata {
    name      = "grafana-oidc"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    clientId     = var.sso_client_id
    clientSecret = var.sso_client_secret
  }
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    password = var.stable_secrets.grafana_admin_password
  }
}

resource "kubernetes_secret" "pgadmin" {
  metadata {
    name      = "pgadmin"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    clientId      = var.sso_client_id
    clientSecret  = var.sso_client_secret
    allowedLogins = var.github_user
    password      = var.stable_secrets.pgadmin_admin_password

    pgpass = join("\n", [
      "hempire-db-rw.env-prod.svc.cluster.local:5432:*:hempire:${var.stable_secrets.hempire_db_password}",
      "hempire-db-rw.env-test.svc.cluster.local:5432:*:hempire:${var.stable_secrets.hempire_db_password}",
      "zitadel-db-rw.zitadel.svc.cluster.local:5432:*:zitadel:${var.stable_secrets.zitadel_db_password}",
      "postgres-rw.home-services.svc.cluster.local:5432:*:immich:${var.stable_secrets.immich_db_password}",
      "postgres-rw.home-services.svc.cluster.local:5432:*:paperless:${var.stable_secrets.paperless_db_password}",
    ])
  }
}

resource "kubernetes_secret" "cloudflare" {
  metadata {
    name      = "cloudflare"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    api-token = var.cloudflare_api_token
  }
}

resource "kubernetes_secret" "cloudflare_hempire" {
  metadata {
    name      = "cloudflare-hempire"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    api-token = var.cloudflare_hempire_api_token
  }
}

resource "kubernetes_secret" "zitadel" {
  metadata {
    name      = "zitadel"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    masterkey      = var.zitadel_masterkey
    admin-password = var.stable_secrets.zitadel_admin_password
    db-password    = var.stable_secrets.zitadel_db_password
  }
}

locals {
  nas_http = {
    protocol      = "https"
    host          = var.nas.host
    port          = 443
    apiKey        = var.truenas_api_key
    allowInsecure = true
  }

  iscsi_target = {
    targetPortal = var.nas.iscsi_portal
    targetGroups = [{
      targetGroupPortalGroup    = 1
      targetGroupInitiatorGroup = 1
      targetGroupAuthType       = "None"
    }]
    extentInsecureTpc              = true
    extentDisablePhysicalBlocksize = true
    extentBlocksize                = 512
    extentRpm                      = "SSD"
  }

  block_name_prefixes = {
    backed    = "csi-b-"
    transient = "csi-t-"
  }

  csi_configs = {
    for class, prefix in local.block_name_prefixes : "block-${class}" => {
      driver         = "freenas-api-iscsi"
      httpConnection = local.nas_http
      zfs = {
        datasetParentName                  = "${var.nas.dataset}/block/${class}/v"
        detachedSnapshotsDatasetParentName = "${var.nas.dataset}/block/${class}/s"
        zvolBlocksize                      = "16K"
        zvolEnableReservation              = false
      }
      iscsi = merge(local.iscsi_target, { namePrefix = prefix })
    }
  }
}

resource "kubernetes_secret" "democratic_csi" {
  for_each = local.csi_configs

  metadata {
    name      = "democratic-csi-${each.key}"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    "driver-config-file.yaml" = yamlencode(each.value)
  }
}

resource "kubernetes_secret" "s3" {
  metadata {
    name      = "s3"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    access-key = var.s3_access_key
    secret-key = var.s3_secret_key
  }
}

resource "kubernetes_secret" "volsync_restic" {
  metadata {
    name      = "volsync-restic"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    RESTIC_PASSWORD       = var.stable_secrets.volsync_restic_password
    AWS_ACCESS_KEY_ID     = var.s3_access_key
    AWS_SECRET_ACCESS_KEY = var.s3_secret_key
  }
}

resource "kubernetes_secret" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = var.app_secrets
}

resource "kubernetes_secret" "registry_pull" {
  metadata {
    name      = "registry-pull"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    dockerconfigjson = local.registry_dockerconfig
  }
}

resource "kubernetes_secret" "zot" {
  metadata {
    name      = "zot"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    ciPasswordHash     = var.registry_ci_password_hash
    pullerPasswordHash = var.registry_puller_password_hash
  }
}

resource "kubernetes_secret" "gitops_repo" {
  for_each = var.gitops_repos

  metadata {
    name      = "gitops-${each.key}"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = each.value
    username = var.github_user
    password = var.gitops_tokens[each.key]
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [yamlencode({
    notifications = {
      enabled = false
    }
  })]

  depends_on = [kubernetes_secret.gitops_repo]
}

resource "null_resource" "app_of_apps" {
  triggers = {
    platform = var.platform_repo
    argocd   = helm_release.argocd.id
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = pathexpand(var.kubeconfig_path)
    }
    command = "kubectl apply -k ${var.platform_path}"
  }
}

resource "kubernetes_secret" "home_db" {
  metadata {
    name      = "home-db"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    immich    = var.stable_secrets.immich_db_password
    paperless = var.stable_secrets.paperless_db_password
  }
}

resource "kubernetes_secret" "home_misc" {
  metadata {
    name      = "home-misc"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    meilisearch-master-key         = var.stable_secrets.meilisearch_master_key
    karakeep-nextauth-secret       = var.stable_secrets.karakeep_nextauth_secret
    paperless-secret-key           = var.stable_secrets.paperless_secret_key
    paperless-admin-password       = var.stable_secrets.paperless_admin_password
    couchdb-password               = var.stable_secrets.couchdb_password
    couchdb-secret                 = var.stable_secrets.couchdb_secret
    couchdb-erlang-cookie          = var.stable_secrets.couchdb_erlang_cookie
    immichframe-api-key            = var.immichframe_api_key
    paperless-r2-access-key-id     = var.paperless_r2_access_key_id
    paperless-r2-secret-access-key = var.paperless_r2_secret_access_key
    cloudflare-account-id          = var.cloudflare_account_id
  }
}

resource "kubernetes_secret" "plex" {
  metadata {
    name      = "plex"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    claim-token = var.plex_claim_token
  }
}

resource "kubernetes_secret" "renovate" {
  metadata {
    name      = "renovate"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    token = var.renovate_token
  }
}

resource "kubernetes_labels" "egress" {
  for_each = toset(var.egress_nodes)

  api_version = "v1"
  kind        = "Node"

  metadata {
    name = each.key
  }

  labels = {
    egress = "vpn"
  }
}

resource "kubernetes_node_taint" "egress" {
  for_each = toset(var.egress_nodes)

  metadata {
    name = each.key
  }

  taint {
    key    = "egress"
    value  = "vpn"
    effect = "NoSchedule"
  }

  force = true
}
