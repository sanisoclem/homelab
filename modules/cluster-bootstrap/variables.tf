variable "gitops_repos" {
  type        = map(string)
  description = "Every repository Argo CD reconciles, as name => https URL. Each gets an AppProject of its own so no repo's Applications can touch another's"

  validation {
    condition     = alltrue([for url in values(var.gitops_repos) : startswith(url, "https://")])
    error_message = "every gitops repo url must be an https:// URL; Argo CD authenticates with a PAT, not a key."
  }
}

variable "gitops_tokens" {
  type        = map(string)
  description = "Fine-grained PAT with Contents: Read for each entry of gitops_repos, keyed the same way. One per repo, so no repo's credential can read another's"
  sensitive   = true

  validation {
    condition     = alltrue([for token in values(var.gitops_tokens) : length(token) > 0])
    error_message = "every gitops repo needs a token."
  }
}

variable "platform_repo" {
  type        = string
  description = "Key in gitops_repos of the repo holding the platform. It is the only one applied imperatively; it declares the Applications that pull in the rest"

  validation {
    condition     = contains(keys(var.gitops_repos), var.platform_repo)
    error_message = "platform_repo must name one of the gitops_repos keys."
  }
}

variable "platform_path" {
  type        = string
  description = "Local path to a checkout of the platform repo, relative to the root module directory. Its root kustomization is applied once, because Argo CD cannot reconcile the Application that tells it what to reconcile"
}

variable "egress_nodes" {
  type        = list(string)
  description = "Workers holding an interface on the egress VLAN. They are labelled and tainted here rather than in the machine config, because NodeRestriction forbids a worker setting either on itself"
  default     = []
}

variable "kubeconfig_path" {
  type        = string
  description = "Where the cluster's kubeconfig is written; the one-shot apply reads it"
}

variable "argocd_chart_version" {
  type        = string
  description = "argo-cd Helm chart version"
}

variable "github_user" {
  type        = string
  description = "GitHub account the repo tokens and the registry token belong to"
}

variable "ghcr_token" {
  type        = string
  description = "Classic PAT with the read:packages scope, for pulling app images. GHCR rejects fine-grained tokens, so this one cannot be scoped to a repository"
  sensitive   = true

  validation {
    condition     = length(var.ghcr_token) > 0
    error_message = "ghcr_token must not be empty."
  }
}

variable "registry_host" {
  type        = string
  description = "Host the cluster's own image registry answers on. It is the name in every app image reference, so it must match the one the gitops repos use"

  validation {
    condition     = length(var.registry_host) > 0
    error_message = "registry_host must not be empty."
  }
}

variable "registry_ci_password_hash" {
  type        = string
  description = "bcrypt hash of the registry's ci password, as htpasswd writes it. The plaintext belongs to the build pipeline and is never held here"
  sensitive   = true

  validation {
    condition     = length(var.registry_ci_password_hash) > 0
    error_message = "registry_ci_password_hash must not be empty."
  }
}

variable "registry_puller_password_hash" {
  type        = string
  description = "bcrypt hash of the registry's puller password, as htpasswd writes it. It must hash registry_puller_password or no pod can pull"
  sensitive   = true

  validation {
    condition     = length(var.registry_puller_password_hash) > 0
    error_message = "registry_puller_password_hash must not be empty."
  }
}

variable "registry_puller_password" {
  type        = string
  description = "Password the pull secret presents as the registry's puller user. Written once by scripts/registry-credentials.sh and reused, so the secret does not churn on every apply. Nothing restored depends on it: regenerate it and the next apply reconciles"
  sensitive   = true

  validation {
    condition     = length(var.registry_puller_password) > 0
    error_message = "registry_puller_password must not be empty."
  }
}

variable "sso_client_id" {
  type        = string
  description = "Client ID of the GitHub OAuth app both Argo CD and Grafana authenticate against; it carries a redirect URI for each"
  sensitive   = true
}

variable "sso_client_secret" {
  type        = string
  description = "Client secret of that OAuth app"
  sensitive   = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with Zone:DNS:Edit on the parent domain; cert-manager solves DNS-01 with it"
  sensitive   = true

  validation {
    condition     = length(var.cloudflare_api_token) > 0
    error_message = "cloudflare_api_token must not be empty."
  }
}

variable "cloudflare_hempire_api_token" {
  type        = string
  description = "Cloudflare API token for the hempire zone. cert-manager picks a DNS-01 solver by zone, so a certificate for that domain is issued with this credential rather than the cluster's"
  sensitive   = true
  default     = ""
}

variable "zitadel_masterkey" {
  type        = string
  description = "Zitadel symmetric-encryption masterkey, exactly 32 chars. NEVER change it while Zitadel is live — everything it has encrypted becomes unreadable"
  sensitive   = true

  validation {
    condition     = length(var.zitadel_masterkey) == 32
    error_message = "zitadel_masterkey must be exactly 32 characters."
  }
}

variable "nas" {
  type = object({
    host         = string
    dataset      = string
    iscsi_portal = string
  })
  description = "Where democratic-csi provisions volumes. dataset is a ZFS path such as tank/k8s, not a mount point — the driver creates a zvol or a child dataset under it per volume"
}

variable "truenas_api_key" {
  type        = string
  description = "TrueNAS API key democratic-csi drives the NAS with. It creates a zvol per iSCSI volume and a dataset per NFS volume, so it needs an account that can do both"
  sensitive   = true

  validation {
    condition     = length(var.truenas_api_key) > 0
    error_message = "truenas_api_key must not be empty; without it no PersistentVolume can be provisioned."
  }
}

variable "s3_access_key" {
  type        = string
  description = "MinIO access key for the bucket holding CNPG backups and the Loki and Tempo chunks"
  sensitive   = true
}

variable "s3_secret_key" {
  type        = string
  description = "MinIO secret key for that bucket"
  sensitive   = true
}

variable "app_secrets" {
  type        = map(string)
  description = "App secrets shared by every environment on this cluster; each key becomes a key of the app-secrets source Secret"
  sensitive   = true
  default     = {}
}

variable "plex_claim_token" {
  type        = string
  description = "Plex claim token from plex.tv/claim, valid for four minutes. Only needed the first time a server is registered"
  sensitive   = true
  default     = ""
}

variable "immichframe_api_key" {
  type        = string
  description = "Immich API key ImmichFrame reads the library with. Generated inside Immich, so it cannot be created here"
  sensitive   = true
  default     = ""
}

variable "paperless_r2_access_key_id" {
  type        = string
  description = "Access key ID of the R2 token the paperless r2-inbox sidecar pulls emailed documents with. Created in the Cloudflare dashboard, so it cannot be created here"
  sensitive   = true
  default     = ""
}

variable "paperless_r2_secret_access_key" {
  type        = string
  description = "Secret access key of the R2 token the paperless r2-inbox sidecar pulls emailed documents with"
  sensitive   = true
  default     = ""
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID, used to build the R2 endpoint"
  default     = ""
}

variable "renovate_token" {
  type        = string
  description = "GitHub PAT the in-cluster Renovate opens pull requests with. Fine-grained, Contents and Pull requests write on every repo it should maintain — it discovers repositories from what the token can see, so the token is the scope"
  sensitive   = true
  default     = ""
}

variable "stable_secrets" {
  type = object({
    grafana_admin_password   = string
    pgadmin_admin_password   = string
    zitadel_admin_password   = string
    hempire_db_password      = string
    zitadel_db_password      = string
    immich_db_password       = string
    paperless_db_password    = string
    meilisearch_master_key   = string
    karakeep_nextauth_secret = string
    paperless_secret_key     = string
    paperless_admin_password = string
    couchdb_password         = string
    couchdb_secret           = string
    couchdb_erlang_cookie    = string
    volsync_restic_password  = string
  })
  description = "Secrets that restored data depends on. Generated once and kept in .env, so a rebuilt cluster opens the databases, volumes and backups the old one wrote"
  sensitive   = true

  validation {
    condition     = alltrue([for secret in values(var.stable_secrets) : length(secret) > 0])
    error_message = "every stable secret must be set; generate a missing one once with `openssl rand -hex 32` and keep it."
  }
}
