variable "cluster_name" {
  type        = string
  description = "Name of the cluster; also the prefix of every VM's name and hostname"
}

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API base URL, e.g. https://pve.lan:8006"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node every VM is created on"
}

variable "proxmox_api_token" {
  type        = string
  description = "Proxmox API token as user@realm!tokenid=uuid. Needs VM.Allocate, VM.Config.*, VM.PowerMgmt and Datastore.AllocateSpace"
  sensitive   = true
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification against the Proxmox API. A default Proxmox install serves a self-signed certificate"
  default     = true
}

variable "proxmox_ssh_username" {
  type        = string
  description = "User the provider uploads snippets as. Snippets cannot go through the API, so this is separate from the API token"
  default     = "root"
}

variable "proxmox_ssh_private_key" {
  type        = string
  description = "Path to the private key for that user. Empty to use the running ssh-agent instead"
  default     = ""
}

variable "vm_datastore_id" {
  type        = string
  description = "Proxmox datastore holding the node disks and cloud-init drives, e.g. local-zfs"
}

variable "image_datastore_id" {
  type        = string
  description = "Proxmox datastore the Talos disk image is downloaded to; needs the 'iso' content type"
  default     = "local"
}

variable "snippet_datastore_id" {
  type        = string
  description = "Proxmox datastore the per-node machine configs are uploaded to; needs the 'snippets' content type"
  default     = "local"
}

variable "vm_id_base" {
  type        = number
  description = "First VM id; nodes take consecutive ids from here, so the range must be free"
  default     = 900
}

variable "startup_order" {
  type        = number
  description = "Proxmox start order for the nodes. The NAS must carry a lower order, so it is serving before the nodes look for it"
  default     = 10
}

variable "talos_version" {
  type        = string
  description = "Talos release to boot and install, e.g. v1.11.2"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version Talos installs (empty for the Talos release default)"
  default     = ""
}

variable "controlplane_ips" {
  type        = list(string)
  description = "Static address of each control plane node, in CIDR form. etcd needs an odd number of members to hold quorum"
}

variable "worker_ips" {
  type        = list(string)
  description = "Static address of each worker node, in CIDR form"
  default     = []
}

variable "controlplane_vip" {
  type        = string
  description = "Shared address the control planes elect a holder for; it is the cluster endpoint and outlives any one node"
}

variable "node_gateway" {
  type        = string
  description = "Default gateway for the node subnet"
}

variable "nameservers" {
  type        = list(string)
  description = "Resolvers the nodes use"
  default     = ["1.1.1.1", "1.0.0.1"]
}

variable "bridge" {
  type        = string
  description = "Proxmox bridge every node attaches to, e.g. vmbr0"
  default     = "vmbr0"
}

variable "vlan_id" {
  type        = number
  description = "VLAN tag for the node interfaces; null for an untagged bridge"
  default     = null
}

variable "controlplane_vcpu" {
  type        = number
  description = "vCPUs given to each control plane node"
  default     = 2
}

variable "controlplane_memory_mb" {
  type        = number
  description = "RAM in MiB given to each control plane node"
  default     = 4096
}

variable "worker_vcpu" {
  type        = number
  description = "vCPUs given to each worker node"
  default     = 4
}

variable "worker_memory_mb" {
  type        = number
  description = "RAM in MiB given to each worker node"
  default     = 10240
}

variable "disk_gb" {
  type        = number
  description = "Size of each node's system disk in GiB. It holds the OS and its images; persistent data lives on the NAS"
  default     = 64
}

variable "dockerhub_username" {
  type        = string
  description = "Docker Hub user for authenticated pulls. Empty to pull anonymously and share one rate limit per public IP"
  default     = ""
  sensitive   = true
}

variable "dockerhub_token" {
  type        = string
  description = "Docker Hub personal access token, public-repo-read scope"
  default     = ""
  sensitive   = true
}

variable "gateway_ip" {
  type        = string
  description = "Address MetalLB gives the nginx Gateway; the wildcard DNS record points here. Must fall inside metallb_pool"
}

variable "metallb_pool" {
  type        = string
  description = "Range MetalLB allocates LoadBalancer addresses from, as first-last. Must sit outside whatever the DHCP server hands out and outside the node and VIP addresses"
}

variable "parent_domain" {
  type        = string
  description = "Registered domain whose Cloudflare zone holds the cluster's records"
}

variable "cluster_subdomain" {
  type        = string
  description = "Cluster's label under parent_domain; services live at *.<sub>.<parent_domain>"
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with Zone:Read and Zone:DNS:Edit on parent_domain, for the wildcard record here and cert-manager's DNS-01 challenges in-cluster"
  sensitive   = true
}

variable "letsencrypt_email" {
  type        = string
  description = "Contact address on the Let's Encrypt account cert-manager registers"
}

variable "nas_host" {
  type        = string
  description = "Address of the TrueNAS VM, used by democratic-csi for both the NFS and iSCSI classes"
}

variable "nas_dataset" {
  type        = string
  description = "ZFS dataset democratic-csi provisions under, e.g. tank/k8s. A dataset path, not a mount point"
}

variable "nas_iscsi_portal" {
  type        = string
  description = "host:port of the TrueNAS iSCSI portal, e.g. 10.11.7.5:3260"
}

variable "s3_endpoint" {
  type        = string
  description = "MinIO endpoint on the NAS holding CNPG backups and the Loki and Tempo chunks"
}

variable "kubeconfig_path" {
  type        = string
  description = "Where to write the cluster's kubeconfig"
}

variable "talosconfig_path" {
  type        = string
  description = "Where to write the cluster's talosconfig"
}
