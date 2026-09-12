#!/usr/bin/env bash
set -euo pipefail

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

if ! state=$(tofu -chdir="$ROOT/cluster" show -json 2>/dev/null); then
  echo "reap: cannot read tofu state, leaving Proxmox alone" >&2
  exit 0
fi

managed=$(printf '%s' "$state" | python3 -c '
import json, sys

def walk(module):
    for resource in module.get("resources", []):
        if resource.get("type") == "proxmox_virtual_environment_vm":
            print(resource["values"]["name"])
    for child in module.get("child_modules", []):
        walk(child)

walk(json.load(sys.stdin).get("values", {}).get("root_module", {}))
')

while read -r vmid name; do
  [ -n "${vmid:-}" ] || continue
  if printf '%s\n' "$managed" | grep -qx "$name"; then
    continue
  fi
  echo "reap: $name ($vmid) is defined but absent from tofu state; removing it"
  pve "qm stop $vmid --skiplock 1" >/dev/null 2>&1 || true
  pve "qm destroy $vmid --purge 1 --destroy-unreferenced-disks 1" >/dev/null 2>&1 || true
done < <(pve "qm list" 2>/dev/null | awk -v c="^${CLUSTER}-" '$2 ~ c { print $1, $2 }')
