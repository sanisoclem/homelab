locals {
  ghcr_dockerconfig = jsonencode({
    auths = {
      "ghcr.io" = {
        auth = base64encode("${var.github_user}:${var.ghcr_token}")
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

resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "random_password" "zitadel_admin" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#%*+-=?_@"
}

resource "random_password" "zitadel_db" {
  length  = 32
  special = false
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
    password = random_password.grafana_admin.result
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
    admin-password = random_password.zitadel_admin.result
    db-password    = random_password.zitadel_db.result
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

  csi_configs = {
    iscsi = {
      driver         = "freenas-api-iscsi"
      httpConnection = local.nas_http
      zfs = {
        datasetParentName                  = "${var.nas.dataset}/iscsi/v"
        detachedSnapshotsDatasetParentName = "${var.nas.dataset}/iscsi/s"
        zvolBlocksize                      = "16K"
        zvolEnableReservation              = false
      }
      iscsi = {
        targetPortal = var.nas.iscsi_portal
        namePrefix   = "csi-"
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
    }

    nfs = {
      driver         = "freenas-api-nfs"
      httpConnection = local.nas_http
      zfs = {
        datasetParentName                  = "${var.nas.dataset}/nfs/v"
        detachedSnapshotsDatasetParentName = "${var.nas.dataset}/nfs/s"
        datasetEnableQuotas                = true
        datasetPermissionsMode             = "0777"
        datasetPermissionsUser             = 0
        datasetPermissionsGroup            = 0
      }
      nfs = {
        shareHost         = var.nas.host
        shareAlldirs      = false
        shareMaprootUser  = "root"
        shareMaprootGroup = "root"
      }
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

resource "kubernetes_secret" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = var.app_secrets
}

resource "kubernetes_secret" "ghcr_pull" {
  metadata {
    name      = "ghcr-pull"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = {
    dockerconfigjson = local.ghcr_dockerconfig
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

resource "random_password" "home_db" {
  for_each = toset(["immich", "paperless"])

  length  = 32
  special = false
}

resource "random_password" "home_misc" {
  for_each = toset([
    "meilisearch-master-key",
    "karakeep-nextauth-secret",
    "paperless-secret-key",
    "couchdb-password",
  ])

  length  = 48
  special = false
}

resource "kubernetes_secret" "home_db" {
  metadata {
    name      = "home-db"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = { for name, password in random_password.home_db : name => password.result }
}

resource "kubernetes_secret" "home_misc" {
  metadata {
    name      = "home-misc"
    namespace = kubernetes_namespace.secrets.metadata[0].name
  }

  data = merge(
    { for name, password in random_password.home_misc : name => password.result },
    { immichframe-api-key = var.immichframe_api_key },
  )
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
