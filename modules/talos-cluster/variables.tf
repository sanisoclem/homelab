variable "cluster_name" {
  type        = string
  description = "Name of the cluster; also the prefix of every VM's name and hostname"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node every VM is created on"
}

variable "talos_version" {
  type        = string
  description = "Talos release to boot and install, e.g. v1.11.2"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_version))
    error_message = "talos_version must be a vMAJOR.MINOR.PATCH tag."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version Talos installs (empty for the Talos release default)"
  default     = ""
}

variable "system_extensions" {
  type        = list(string)
  description = "Official Talos system extensions baked into the Image Factory schematic. iscsi-tools and util-linux-tools are what democratic-csi needs to attach an iSCSI volume; qemu-guest-agent lets Proxmox shut a node down cleanly"
  default = [
    "siderolabs/iscsi-tools",
    "siderolabs/util-linux-tools",
    "siderolabs/qemu-guest-agent",
  ]
}

variable "controlplane_ips" {
  type        = list(string)
  description = "Static address of each control plane node, in CIDR form. etcd needs an odd number of members to hold quorum"

  validation {
    condition     = length(var.controlplane_ips) % 2 == 1
    error_message = "controlplane_ips must hold an odd number of addresses."
  }

  validation {
    condition     = alltrue([for ip in var.controlplane_ips : can(cidrnetmask(ip))])
    error_message = "every controlplane address must carry a prefix length, e.g. 10.11.7.21/24."
  }
}

variable "worker_ips" {
  type        = list(string)
  description = "Static address of each worker node, in CIDR form. Control planes also run workloads, so an empty list is a valid cluster"
  default     = []

  validation {
    condition     = alltrue([for ip in var.worker_ips : can(cidrnetmask(ip))])
    error_message = "every worker address must carry a prefix length, e.g. 10.11.7.31/24."
  }
}

variable "controlplane_vip" {
  type        = string
  description = "Shared address the control planes elect a holder for, without a prefix. It is the cluster endpoint, so it survives losing the node that currently answers on it. Must sit outside both the DHCP range and the MetalLB pool"
}

variable "gateway" {
  type        = string
  description = "Default gateway for the node subnet"
}

variable "nameservers" {
  type        = list(string)
  description = "Resolvers the nodes use"
}

variable "bridge" {
  type        = string
  description = "Proxmox bridge every node attaches to"
}

variable "vlan_id" {
  type        = number
  description = "VLAN tag for the node interfaces; null for an untagged bridge"
  default     = null
}

variable "egress_vlan_id" {
  type        = number
  description = "VLAN that egresses through the site tunnel. A worker given an address on it keeps its ordinary default route on the node subnet; the interface exists so individual pods can be attached to it, which is the only way to use a VLAN that cannot route back to the node subnet"
  default     = null
}

variable "egress_gateway" {
  type        = string
  description = "Default gateway on the egress VLAN"
  default     = ""
}

variable "egress_workers" {
  type        = map(string)
  description = "Workers that get a second interface on the egress VLAN, as worker number => address in CIDR form. They are labelled and tainted egress=vpn, so only workloads that ask for it land there"
  default     = {}
}

variable "controlplane_vcpu" {
  type        = number
  description = "vCPUs given to each control plane node"
}

variable "controlplane_memory_mb" {
  type        = number
  description = "RAM in MiB given to each control plane node"
}

variable "worker_vcpu" {
  type        = number
  description = "vCPUs given to each worker node"
}

variable "worker_memory_mb" {
  type        = number
  description = "RAM in MiB given to each worker node"
}

variable "egress_worker_vcpu" {
  type        = number
  description = "vCPUs for a worker on the egress VLAN. Null to size it like any other worker"
  default     = null
}

variable "egress_worker_memory_mb" {
  type        = number
  description = "RAM in MiB for a worker on the egress VLAN. Only the workloads that need the tunnel are allowed onto it, so it is usually much smaller than a general worker. Null to size it like any other worker"
  default     = null
}

variable "disk_gb" {
  type        = number
  description = "Size of each node's system disk in GiB. It holds the OS and its images; persistent data lives on the NAS, so this does not have to grow with the workload"
}

variable "vm_datastore_id" {
  type        = string
  description = "Proxmox datastore holding the node disks and cloud-init drives, e.g. local-zfs"
}

variable "image_datastore_id" {
  type        = string
  description = "Proxmox datastore the Talos disk image is downloaded to; needs the 'import' content type. Proxmox 9 refuses to import a VM disk from a file stored as 'iso'"
}

variable "snippet_datastore_id" {
  type        = string
  description = "Proxmox datastore the per-node machine configs are uploaded to; needs the 'snippets' content type, and the provider uploads over SSH rather than the API"
}

variable "ssh_host" {
  type        = string
  description = "Host the provider and this module reach Proxmox on over SSH"
}

variable "ssh_username" {
  type        = string
  description = "User to reach the Proxmox host as"
  default     = "root"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Private key for that user; empty to rely on a running ssh-agent"
  default     = ""
}

variable "image_import_dir" {
  type        = string
  description = "Directory backing the image datastore's import content on the Proxmox host. Proxmox refuses to decompress into an import datastore and the Image Factory only publishes zstd, so the image is fetched and decompressed here over SSH rather than by the download-url API"
  default     = "/var/lib/vz/import"
}

variable "vm_id_base" {
  type        = number
  description = "First VM id; nodes take consecutive ids from here, so the range must be free"
  default     = 900
}

variable "startup_order" {
  type        = number
  description = "Proxmox start order for the nodes. Anything the cluster mounts — the NAS especially — must carry a lower order so it is serving before the nodes look for it"
  default     = 10
}

variable "startup_delay" {
  type        = number
  description = "Seconds Proxmox waits after starting one node before starting the next"
  default     = 15
}

variable "dockerhub_username" {
  type        = string
  description = "Docker Hub user for authenticated pulls; anonymous pulls share one rate limit per public IP and this cluster pulls every third-party image directly. Empty to pull anonymously"
  default     = ""
  sensitive   = true
}

variable "dockerhub_token" {
  type        = string
  description = "Docker Hub personal access token, public-repo-read scope"
  default     = ""
  sensitive   = true
}
