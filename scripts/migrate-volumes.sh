#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KUBECONFIG="${TF_VAR_kubeconfig_path:?TF_VAR_kubeconfig_path is not set}"
export KUBECONFIG="${KUBECONFIG/#\~/$HOME}"

BACKED_MOVES=(
  "home-media emby-config emby"
  "home-knowledge paperless-state paperless-data"
)

NFS_MOVES=(
  "home-knowledge paperless-files knowledge/paperless/media"
)

pvc_exists() {
  kubectl -n "$1" get pvc "$2" > /dev/null 2>&1
}

volsync_installed() {
  kubectl get crd replicationsources.volsync.backube > /dev/null 2>&1
}

default_class() {
  kubectl get storageclass -o json |
    jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name'
}

seed_backed_volumes() {
  local move namespace from to
  for move in "${BACKED_MOVES[@]}"; do
    read -r namespace from to <<< "$move"
    pvc_exists "$namespace" "$from" || continue
    pvc_exists "$namespace" "$to" && continue
    "$SCRIPT_DIR/seed-volume.sh" "$namespace" "$from" "$to"
  done
}

copy_volumes_to_nfs() {
  local move namespace pvc subpath
  for move in "${NFS_MOVES[@]}"; do
    read -r namespace pvc subpath <<< "$move"
    pvc_exists "$namespace" "$pvc" || continue
    "$SCRIPT_DIR/copy-volume-to-nfs.sh" "$namespace" "$pvc" "$subpath"
  done
}

moving_pvcs() {
  local move namespace from rest
  for move in "${BACKED_MOVES[@]}" "${NFS_MOVES[@]}"; do
    read -r namespace from rest <<< "$move"
    echo "$namespace/$from"
  done
}

legacy_pvcs() {
  kubectl get pvc -A -o json |
    jq -r '.items[] | select(.spec.storageClassName == "nas-block" and .metadata.deletionTimestamp == null) | "\(.metadata.namespace)/\(.metadata.name)"' |
    grep -vxFf <(moving_pvcs) || true
}

pods_using() {
  kubectl -n "$1" get pods -o json |
    jq -r --arg pvc "$2" '.items[] | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $pvc)) | .metadata.name'
}

recreate_on_default_class() {
  local namespace="${1%/*}" pvc="${1#*/}"
  echo "migrate: recreating $namespace/$pvc on block-transient; its data is not kept"
  kubectl -n "$namespace" delete pvc "$pvc" --wait=false
  pods_using "$namespace" "$pvc" | xargs -r kubectl -n "$namespace" delete pod
  kubectl -n "$namespace" wait "pvc/$pvc" --for=delete --timeout=10m 2> /dev/null || true
  pods_using "$namespace" "$pvc" | xargs -r kubectl -n "$namespace" delete pod
}

recreate_transient_volumes() {
  [ "$(default_class)" = block-transient ] || return 0
  local pvc
  for pvc in $(legacy_pvcs); do
    recreate_on_default_class "$pvc"
  done
}

if ! volsync_installed; then
  echo "migrate: VolSync is not installed yet; push gitops-platform and run task up again"
  exit 0
fi

seed_backed_volumes
copy_volumes_to_nfs
recreate_transient_volumes
echo "migrate: ok"
