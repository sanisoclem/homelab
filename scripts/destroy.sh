#!/usr/bin/env bash

# best effort
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER="${TF_VAR_cluster_name:?TF_VAR_cluster_name is not set}"

expand() { printf '%s' "${1/#\~/$HOME}"; }

pve() {
  local host="${TF_VAR_proxmox_endpoint#*://}"
  local ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
  [ -n "${TF_VAR_proxmox_ssh_private_key:-}" ] && ssh_opts+=(-i "$(expand "${TF_VAR_proxmox_ssh_private_key}")")
  ssh "${ssh_opts[@]}" "${TF_VAR_proxmox_ssh_username:-root}@${host%%:*}" "$@"
}

echo "==> Destroying Argo CD and the source secrets"
tofu -chdir="$ROOT/bootstrap" destroy -auto-approve 2>&1 | tail -3

echo "==> Destroying the VMs and the DNS record"
tofu -chdir="$ROOT/cluster" destroy -auto-approve 2>&1 | tail -3

echo "==> Sweeping Proxmox for anything left behind"
for vmid in $(pve "qm list" 2>/dev/null | awk -v c="^${CLUSTER}-" '$2 ~ c { print $1 }'); do
  echo "    removing VM $vmid"
  pve "qm stop $vmid --skiplock 1" >/dev/null 2>&1
  pve "qm destroy $vmid --purge 1 --destroy-unreferenced-disks 1" >/dev/null 2>&1
done

echo "    removing machine config snippets"
pve "rm -f /var/lib/vz/snippets/${CLUSTER}-*.yaml" >/dev/null 2>&1

echo "==> Removing generated credentials"
for path in "${TF_VAR_kubeconfig_path:-}" "${TF_VAR_talosconfig_path:-}"; do
  [ -n "$path" ] || continue
  rm -f "$(expand "$path")"
done
kubectl config delete-context "admin@${CLUSTER}" >/dev/null 2>&1
