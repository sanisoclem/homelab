variable "kubeconfig_path" {
  type        = string
  description = "Kubeconfig written by the cluster root module"
}

variable "argocd_chart_version" {
  type        = string
  description = "argo-cd Helm chart version"
}

variable "platform_path" {
  type        = string
  description = "Local path to a checkout of the platform repo, relative to this directory. Its root kustomization is the one thing applied by hand"
}

variable "platform_repo_url" {
  type        = string
  description = "HTTPS URL of the platform repo: CRDs, storage, ingress, secrets, observability, Zitadel"
}

variable "platform_token" {
  type        = string
  description = "Fine-grained PAT with Contents: Read on the platform repo"
  sensitive   = true
}

variable "hempire_repo_url" {
  type        = string
  description = "HTTPS URL of the hempire app repo"
}

variable "hempire_token" {
  type        = string
  description = "Fine-grained PAT with Contents: Read on the hempire app repo"
  sensitive   = true
}

variable "home_repo_url" {
  type        = string
  description = "HTTPS URL of the home app repo"
}

variable "home_token" {
  type        = string
  description = "Fine-grained PAT with Contents: Read on the home app repo"
  sensitive   = true
}

variable "github_user" {
  type        = string
  description = "GitHub account the repo tokens and the registry token belong to"
}

variable "ghcr_token" {
  type        = string
  description = "Classic PAT with the read:packages scope, for pulling app images. GHCR rejects fine-grained tokens"
  sensitive   = true
}

variable "registry_host" {
  type        = string
  description = "Host the cluster's own image registry answers on, matching the name the gitops repos reference"
}

variable "registry_ci_password_hash" {
  type        = string
  description = "bcrypt hash of the registry's ci password. The plaintext lives in the build pipeline's secrets, not here"
  sensitive   = true
}

variable "registry_puller_password_hash" {
  type        = string
  description = "bcrypt hash of the registry's puller password, which must hash registry_puller_password"
  sensitive   = true
}

variable "registry_puller_password" {
  type        = string
  description = "Password the pull secret presents as the registry's puller user, written by scripts/registry-credentials.sh"
  sensitive   = true
}

variable "sso_client_id" {
  type        = string
  description = "Client ID of the GitHub OAuth app both Argo CD and Grafana authenticate against"
  sensitive   = true
}

variable "sso_client_secret" {
  type        = string
  description = "Client secret of that OAuth app"
  sensitive   = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with Zone:DNS:Edit on the parent domain"
  sensitive   = true
}

variable "cloudflare_hempire_api_token" {
  type        = string
  description = "Cloudflare API token with Zone:DNS:Edit on the hempire domain"
  sensitive   = true
  default     = ""
}

variable "zitadel_masterkey" {
  type        = string
  description = "Zitadel symmetric-encryption masterkey, exactly 32 chars (generate once: tr -dc A-Za-z0-9 </dev/urandom | head -c 32). NEVER change it while Zitadel is live — everything Zitadel has encrypted becomes unreadable"
  sensitive   = true
}

variable "nas_host" {
  type        = string
  description = "Address of the TrueNAS VM"
}

variable "nas_dataset" {
  type        = string
  description = "ZFS dataset democratic-csi provisions under, e.g. tank/k8s. A dataset path, not a mount point"
}

variable "nas_iscsi_portal" {
  type        = string
  description = "host:port of the TrueNAS iSCSI portal, e.g. 10.11.7.5:3260"
}

variable "truenas_api_key" {
  type        = string
  description = "TrueNAS API key democratic-csi provisions both StorageClasses with"
  sensitive   = true
}

variable "s3_access_key" {
  type        = string
  description = "MinIO access key for CNPG backups and the Loki and Tempo chunks"
  sensitive   = true
}

variable "s3_secret_key" {
  type        = string
  description = "MinIO secret key for that bucket"
  sensitive   = true
}

variable "bff_session_secret" {
  type        = string
  description = "BFF session-cookie signing secret (generate: openssl rand -hex 32)"
  sensitive   = true
  default     = ""
}

variable "admin_session_secret" {
  type        = string
  description = "Admin app session-cookie signing secret (generate: openssl rand -hex 32)"
  sensitive   = true
  default     = ""
}

variable "bank_basiq_api_key" {
  type        = string
  description = "Basiq server API key, Basic auth for bank-api and bank-poller"
  sensitive   = true
  default     = ""
}

variable "crm_zitadel_client_secret" {
  type        = string
  description = "Zitadel client secret of the CRM API's confidential OAuth client. Written by `task zitadel:seed`"
  sensitive   = true
  default     = ""
}

variable "bank_client_id" {
  type        = string
  description = "Client ID of the bank domain's Zitadel machine user. Written by `task zitadel:seed`"
  sensitive   = true
  default     = ""
}

variable "bank_client_secret" {
  type        = string
  description = "Client secret of the bank domain's Zitadel machine user. Written by `task zitadel:seed`"
  sensitive   = true
  default     = ""
}

variable "bridge_client_id" {
  type        = string
  description = "Client ID of the bridge domain's Zitadel machine user. Written by `task zitadel:seed`"
  sensitive   = true
  default     = ""
}

variable "bridge_client_secret" {
  type        = string
  description = "Client secret of the bridge domain's Zitadel machine user. Written by `task zitadel:seed`"
  sensitive   = true
  default     = ""
}

variable "budget_client_id" {
  type        = string
  description = "Client ID of the budget domain's Zitadel machine user. Written by `task zitadel:seed`"
  sensitive   = true
  default     = ""
}

variable "budget_client_secret" {
  type        = string
  description = "Client secret of the budget domain's Zitadel machine user. Written by `task zitadel:seed`"
  sensitive   = true
  default     = ""
}

variable "plex_claim_token" {
  type        = string
  description = "Plex claim token from plex.tv/claim, valid for four minutes"
  sensitive   = true
  default     = ""
}

variable "immichframe_api_key" {
  type        = string
  description = "Immich API key ImmichFrame reads the library with; generated inside Immich"
  sensitive   = true
  default     = ""
}

variable "paperless_r2_access_key_id" {
  type        = string
  description = "Access key ID of the R2 token the paperless r2-inbox sidecar pulls emailed documents with"
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
  description = "GitHub PAT the in-cluster Renovate opens pull requests with, fine-grained with Contents and Pull requests write on the gitops repos"
  sensitive   = true
  default     = ""
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana break-glass local admin password"
  sensitive   = true
}

variable "pgadmin_admin_password" {
  type        = string
  description = "pgAdmin break-glass local admin password"
  sensitive   = true
}

variable "zitadel_admin_password" {
  type        = string
  description = "Zitadel break-glass console admin password. Zitadel stores it on first start, so it must match the restored database"
  sensitive   = true
}

variable "hempire_db_password" {
  type        = string
  description = "Password of the hempire Postgres role"
  sensitive   = true
}

variable "zitadel_db_password" {
  type        = string
  description = "Password of the zitadel Postgres role"
  sensitive   = true
}

variable "immich_db_password" {
  type        = string
  description = "Password of the immich Postgres role"
  sensitive   = true
}

variable "paperless_db_password" {
  type        = string
  description = "Password of the paperless Postgres role"
  sensitive   = true
}

variable "meilisearch_master_key" {
  type        = string
  description = "Meilisearch master key"
  sensitive   = true
}

variable "karakeep_nextauth_secret" {
  type        = string
  description = "Karakeep NextAuth session secret"
  sensitive   = true
}

variable "paperless_secret_key" {
  type        = string
  description = "Paperless Django secret key"
  sensitive   = true
}

variable "paperless_admin_password" {
  type        = string
  description = "Paperless admin password, stored in the database on first start"
  sensitive   = true
}

variable "couchdb_password" {
  type        = string
  description = "CouchDB admin password Obsidian LiveSync clients log in with"
  sensitive   = true
}

variable "couchdb_secret" {
  type        = string
  description = "CouchDB cookie-auth secret"
  sensitive   = true
}

variable "couchdb_erlang_cookie" {
  type        = string
  description = "CouchDB Erlang distribution cookie"
  sensitive   = true
}

variable "volsync_restic_password" {
  type        = string
  description = "Encryption password of every VolSync restic repository. Losing it makes the block-volume backups unreadable"
  sensitive   = true
}
