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

variable "truenas_ssh_private_key" {
  type        = string
  description = "Private key democratic-csi uses for the few operations TrueNAS exposes over SSH rather than its API. Empty if the driver is configured API-only"
  sensitive   = true
  default     = ""
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
