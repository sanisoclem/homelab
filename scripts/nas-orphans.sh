#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/truenas.sh"

KUBECONFIG="${TF_VAR_kubeconfig_path:?TF_VAR_kubeconfig_path is not set}"
export KUBECONFIG="${KUBECONFIG/#\~/$HOME}"

bound_volumes() {
  kubectl get pv -o json | jq -r '.items[].spec.csi.volumeHandle // empty'
}

cluster_zvols() {
  nas GET "pool/dataset?type=VOLUME&limit=0" |
    jq -r --arg root "$K8S_DATASET/" '.[] | select(.name | startswith($root)) | [.name, .used.parsed] | @tsv'
}

bound=$(bound_volumes)
cluster_zvols | while IFS=$'\t' read -r zvol used; do
  grep -qxF "${zvol##*/}" <<< "$bound" && continue
  printf '%8s  %s\n' "$(numfmt --to=iec "$used")" "$zvol"
done
