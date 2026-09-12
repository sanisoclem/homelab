locals {
  controlplanes = {
    for index, address in var.controlplane_ips :
    "${var.cluster_name}-cp-${index + 1}" => { type = "controlplane", address = address, index = index, egress = null }
  }

  workers = {
    for index, address in var.worker_ips :
    "${var.cluster_name}-worker-${index + 1}" => {
      type    = "worker"
      address = address
      index   = length(var.controlplane_ips) + index
      egress  = lookup(var.egress_workers, tostring(index + 1), null)
    }
  }

  nodes = merge(local.controlplanes, local.workers)

  first_controlplane = sort(keys(local.controlplanes))[0]

  macs = {
    for name, _ in local.nodes : name => format(
      "BC:24:11:%s:%s:%s",
      substr(sha1(name), 0, 2), substr(sha1(name), 2, 2), substr(sha1(name), 4, 2)
    )
  }

  egress_macs = {
    for name, _ in local.nodes : name => format(
      "BC:24:11:%s:%s:%s",
      substr(sha1("${name}-egress"), 0, 2), substr(sha1("${name}-egress"), 2, 2), substr(sha1("${name}-egress"), 4, 2)
    )
  }

  node_subnet = "${cidrhost(var.controlplane_ips[0], 0)}/${split("/", var.controlplane_ips[0])[1]}"

  node_memory = {
    for name, node in local.nodes : name => (
      node.type == "controlplane" ? var.controlplane_memory_mb :
      node.egress != null && var.egress_worker_memory_mb != null ? var.egress_worker_memory_mb :
      var.worker_memory_mb
    )
  }

  node_vcpu = {
    for name, node in local.nodes : name => (
      node.type == "controlplane" ? var.controlplane_vcpu :
      node.egress != null && var.egress_worker_vcpu != null ? var.egress_worker_vcpu :
      var.worker_vcpu
    )
  }
  ips           = { for name, node in local.nodes : name => split("/", node.address)[0] }
  endpoint      = "https://${var.controlplane_vip}:6443"
  api_addresses = concat([var.controlplane_vip], [for name, _ in local.controlplanes : local.ips[name]])

  dockerhub_config = var.dockerhub_username == "" ? {} : {
    "docker.io" = {
      auth = {
        username = var.dockerhub_username
        password = var.dockerhub_token
      }
    }
  }

  machine_patch = {
    machine = {
      install = {
        disk  = "/dev/vda"
        image = data.talos_image_factory_urls.this.urls.installer
      }
      certSANs = local.api_addresses
      registries = {
        config = local.dockerhub_config
      }
      kubelet = {
        nodeIP = {
          validSubnets = [local.node_subnet]
        }
        extraMounts = [{
          destination = "/var/mnt/local-path-provisioner"
          type        = "bind"
          source      = "/var/mnt/local-path-provisioner"
          options     = ["bind", "rshared", "rw"]
        }]
      }
    }
  }

  controlplane_patch = {
    cluster = {
      allowSchedulingOnControlPlanes = true
      network = {
        cni = {
          name = "flannel"
          flannel = {
            extraArgs = ["--iface-can-reach=${var.gateway}"]
          }
        }
      }
      apiServer = {
        certSANs = local.api_addresses
        admissionControl = [{
          name = "PodSecurity"
          configuration = {
            apiVersion = "pod-security.admission.config.k8s.io/v1alpha1"
            kind       = "PodSecurityConfiguration"
            defaults = {
              enforce         = "privileged"
              enforce-version = "latest"
              audit           = "restricted"
              audit-version   = "latest"
              warn            = "restricted"
              warn-version    = "latest"
            }
          }
        }]
      }
    }
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.system_extensions
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
  architecture  = "amd64"
}

resource "proxmox_download_file" "talos" {
  node_name    = var.proxmox_node
  datastore_id = var.image_datastore_id
  content_type = "iso"

  url                     = data.talos_image_factory_urls.this.urls.disk_image
  file_name               = "talos-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 8)}-nocloud-amd64.img"
  decompression_algorithm = "zst"
  overwrite               = false
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "node" {
  for_each = local.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.endpoint
  machine_type       = each.value.type
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version == "" ? null : var.kubernetes_version

  config_patches = concat(
    [
      yamlencode(local.machine_patch),
      yamlencode(merge(
        {
          machine = {
            network = {
              hostname    = each.key
              nameservers = var.nameservers
              interfaces = concat(
                [merge(
                  {
                    deviceSelector = { hardwareAddr = lower(local.macs[each.key]) }
                    addresses      = [each.value.address]
                    routes         = each.value.egress == null ? [{ network = "0.0.0.0/0", gateway = var.gateway }] : []
                  },
                  each.value.type == "controlplane" ? { vip = { ip = var.controlplane_vip } } : {},
                )],
                each.value.egress == null ? [] : [{
                  deviceSelector = { hardwareAddr = lower(local.egress_macs[each.key]) }
                  addresses      = [each.value.egress]
                  routes         = [{ network = "0.0.0.0/0", gateway = var.egress_gateway }]
                }],
              )
            }
          }
        },
        each.value.egress == null ? {} : {
          machine = {
            nodeLabels = { egress = "vpn" }
            nodeTaints = { egress = "vpn:NoSchedule" }
          }
        },
      )),
      yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", "$patch" = "delete" }),
    ],
    each.value.type == "controlplane" ? [yamlencode(local.controlplane_patch)] : [],
  )
}

resource "proxmox_virtual_environment_file" "machine_config" {
  for_each = local.nodes

  node_name    = var.proxmox_node
  datastore_id = var.snippet_datastore_id
  content_type = "snippets"

  source_raw {
    data      = data.talos_machine_configuration.node[each.key].machine_configuration
    file_name = "${each.key}.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  name      = each.key
  node_name = var.proxmox_node
  vm_id     = var.vm_id_base + each.value.index
  on_boot   = true
  machine   = "q35"
  bios      = "seabios"

  memory {
    dedicated = local.node_memory[each.key]
    floating  = local.node_memory[each.key]
  }

  cpu {
    cores = local.node_vcpu[each.key]
    type  = "host"
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = var.vm_datastore_id
    import_from  = proxmox_download_file.talos.id
    interface    = "virtio0"
    size         = var.disk_gb
    iothread     = true
    discard      = "on"
  }

  network_device = concat(
    [{
      bridge       = var.bridge
      mac_address  = local.macs[each.key]
      vlan_id      = var.vlan_id
      model        = "virtio"
      enabled      = true
      firewall     = false
      disconnected = false
      mtu          = null
      queues       = null
      rate_limit   = null
      trunks       = null
    }],
    each.value.egress == null ? [] : [{
      bridge       = var.bridge
      mac_address  = local.egress_macs[each.key]
      vlan_id      = var.egress_vlan_id
      model        = "virtio"
      enabled      = true
      firewall     = false
      disconnected = false
      mtu          = null
      queues       = null
      rate_limit   = null
      trunks       = null
    }],
  )

  initialization {
    datastore_id      = var.vm_datastore_id
    user_data_file_id = proxmox_virtual_environment_file.machine_config[each.key].id
  }

  startup {
    order    = var.startup_order
    up_delay = var.startup_delay
  }

  lifecycle {
    ignore_changes = [initialization[0].user_data_file_id]
  }
}

resource "null_resource" "api_up" {
  for_each = local.nodes

  triggers = {
    vm = proxmox_virtual_environment_vm.node[each.key].id
  }

  provisioner "local-exec" {
    command = <<-SH
      for _ in $(seq 1 120); do
        if timeout 2 bash -c '</dev/tcp/${local.ips[each.key]}/50000' 2>/dev/null; then exit 0; fi
        sleep 5
      done
      echo "talos api at ${local.ips[each.key]}:50000 never came up" >&2
      exit 1
    SH
  }
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = local.ips[each.key]

  depends_on = [null_resource.api_up]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.ips[local.first_controlplane]

  depends_on = [talos_machine_configuration_apply.node]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for name, _ in local.controlplanes : local.ips[name]]
  nodes                = values(local.ips)
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.ips[local.first_controlplane]

  depends_on = [talos_machine_bootstrap.this]
}

resource "null_resource" "cluster_ready" {
  triggers = {
    kubeconfig = talos_cluster_kubeconfig.this.id
  }

  provisioner "local-exec" {
    command = <<-SH
      for _ in $(seq 1 120); do
        if timeout 2 bash -c '</dev/tcp/${var.controlplane_vip}/6443' 2>/dev/null; then exit 0; fi
        sleep 5
      done
      echo "kubernetes api at ${var.controlplane_vip}:6443 never came up" >&2
      exit 1
    SH
  }
}
