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

cluster_zvols() {
  nas GET "pool/dataset?type=VOLUME&limit=0" |
    jq -c --arg root "$K8S_DATASET/" \
      '[.[] | select(.name | startswith($root))
            | {name, created: (.creation.rawvalue | tonumber),
               origin: ((.origin.rawvalue // "") | sub("@.*"; ""))}]'
}

unused_zvols() {
  local zvols="$1" bound="$2" oldest
  oldest=$(($(date +%s) - MINIMUM_AGE_SECONDS))
  jq -r --argjson oldest "$oldest" '.[] | select(.created < $oldest) | .name' <<< "$zvols" |
    while read -r zvol; do
      grep -qxF "${zvol##*/}" <<< "$bound" || echo "$zvol"
    done
}

clones_of() {
  jq -r --arg origin "$2" '.[] | select(.origin == $origin) | .name' <<< "$1"
}

surviving_clone() {
  local zvols="$1" zvol="$2" destroyed="$3" clone
  while read -r clone; do
    [ -n "$clone" ] || continue
    grep -qxF "$clone" <<< "$destroyed" || { echo "$clone"; return 0; }
  done < <(clones_of "$zvols" "$zvol")
  return 1
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
  local zvols bound connected unused destroyed deferred progress zvol clone
  zvols=$(cluster_zvols)
  bound=$(bound_volumes)
  connected=$(connected_targets)
  unused=$(unused_zvols "$zvols" "$bound")
  destroyed=""
  progress=1

  while [ -n "$unused" ] && [ "$progress" -ne 0 ]; do
    progress=0
    deferred=""
    while read -r zvol; do
      [ -n "$zvol" ] || continue
      if surviving_clone "$zvols" "$zvol" "$destroyed" > /dev/null; then
        deferred+="$zvol"$'\n'
        continue
      fi
      detach "$zvol" "$connected" || continue
      if ! destroy "$zvol"; then
        echo "reap: could not destroy $zvol, leaving it" >&2
        continue
      fi
      destroyed+="$zvol"$'\n'
      progress=$((progress + 1))
      echo "reap: destroyed $zvol"
    done <<< "$unused"
    unused="${deferred%$'\n'}"
  done

  while read -r zvol; do
    [ -n "$zvol" ] || continue
    clone=$(surviving_clone "$zvols" "$zvol" "$destroyed") || continue
    echo "reap: $zvol is the origin of $clone, leaving it" >&2
  done <<< "$unused"
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
