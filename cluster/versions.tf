terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent    = var.proxmox_ssh_private_key == ""
    username = var.proxmox_ssh_username

    private_key = var.proxmox_ssh_private_key == "" ? null : file(pathexpand(var.proxmox_ssh_private_key))
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "cloudflare" {
  alias     = "hempire"
  api_token = var.cloudflare_hempire_api_token
}
