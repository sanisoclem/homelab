#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/truenas.sh"

KUBECONFIG="${TF_VAR_kubeconfig_path:?TF_VAR_kubeconfig_path is not set}"
export KUBECONFIG="${KUBECONFIG/#\~/$HOME}"

MINIMUM_AGE_SECONDS=3600

delete_released_volumes() {
  kubectl get pv -o json |
    jq -r '.items[] | select(.status.phase == "Released" and (.spec.csi.driver // "" | startswith("org.democratic-csi."))) | .metadata.name' |
    xargs -r kubectl delete pv
}

bound_volumes() {
  kubectl get pv -o json | jq -r '.items[].spec.csi.volumeHandle // empty'
}

connected_targets() {
  nas POST iscsi/global/sessions -d '{}' | jq -r '.[].target | sub("^[^:]*:"; "")'
}

unused_zvols() {
  local bound="$1" oldest
  oldest=$(($(date +%s) - MINIMUM_AGE_SECONDS))
  nas GET "pool/dataset?type=VOLUME&limit=0" |
    jq -r --arg root "$K8S_DATASET/" --argjson oldest "$oldest" \
      '.[] | select((.name | startswith($root)) and (.creation.rawvalue | tonumber) < $oldest) | .name' |
    while read -r zvol; do
      grep -qxF "${zvol##*/}" <<< "$bound" || echo "$zvol"
    done
}

detach() {
  local zvol="$1" connected="$2" extent mapping target
  extent=$(nas GET iscsi/extent | jq -c --arg disk "zvol/$zvol" 'first(.[] | select(.disk == $disk)) // empty')
  [ -n "$extent" ] || return 0
  if grep -qxF "$(jq -r .name <<< "$extent")" <<< "$connected"; then
    echo "reap: $zvol has an iSCSI session, leaving it" >&2
    return 1
  fi
  mapping=$(nas GET "iscsi/targetextent?extent=$(jq -r .id <<< "$extent")" | jq -r 'first(.[] | "\(.id) \(.target)") // empty')
  if [ -n "$mapping" ]; then
    read -r mapping target <<< "$mapping"
    nas DELETE "iscsi/targetextent/id/$mapping" > /dev/null
    nas DELETE "iscsi/target/id/$target" > /dev/null
  fi
  nas DELETE "iscsi/extent/id/$(jq -r .id <<< "$extent")" > /dev/null
}

destroy() {
  nas DELETE "pool/dataset/id/$(uri "$1")" -d '{"recursive": true}' > /dev/null
}

reap_unused_zvols() {
  local bound connected zvol
  bound=$(bound_volumes)
  connected=$(connected_targets)
  for zvol in $(unused_zvols "$bound"); do
    detach "$zvol" "$connected" || continue
    destroy "$zvol"
    echo "reap: destroyed $zvol"
  done
}

holds_volumes() {
  nas GET "pool/dataset/id/$(uri "$1")" | jq -e '[.. | objects | select(.type? == "VOLUME")] | length > 0' > /dev/null
}

remove_legacy_datasets() {
  kubectl get storageclass -o name | grep -qE '/(nas-block|nas-file)$' && return 0
  local legacy
  for legacy in "$K8S_DATASET/iscsi" "$K8S_DATASET/nfs"; do
    nas GET "pool/dataset?id=$(uri "$legacy")" | jq -e 'length > 0' > /dev/null || continue
    holds_volumes "$legacy" && continue
    destroy "$legacy"
    echo "reap: removed legacy dataset $legacy"
  done
}

delete_released_volumes
reap_unused_zvols
remove_legacy_datasets
echo "reap: ok"
