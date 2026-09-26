#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/truenas.sh"

TRUECLOUD_PASSWORD="${TRUECLOUD_PASSWORD:?TRUECLOUD_PASSWORD is not set; it is the encryption password of the Storj backups}"
STORJ_BUCKET="${STORJ_BUCKET:?STORJ_BUCKET is not set}"
USER_DATASET="${NAS_USER_DATASET:?NAS_USER_DATASET is not set}"
SERVICE_DATASET="${NAS_SERVICE_DATASET:?NAS_SERVICE_DATASET is not set}"
SCRATCH_DATASET="${NAS_SCRATCH_DATASET:?NAS_SCRATCH_DATASET is not set}"
S3_DATASET="${NAS_S3_DATASET:?NAS_S3_DATASET is not set}"
NFS_CLIENTS=$(jq -cn \
  --argjson controlplanes "${TF_VAR_controlplane_ips:?TF_VAR_controlplane_ips is not set}" \
  --argjson workers "${TF_VAR_worker_ips:?TF_VAR_worker_ips is not set}" \
  '$controlplanes + $workers | map(sub("/.*"; "") + "/32") | sort')

dataset_exists() {
  nas GET "pool/dataset?id=$(uri "$1")" | jq -e 'length > 0' > /dev/null
}

ensure_dataset() {
  dataset_exists "$1" && return
  echo "nas: creating dataset $1"
  nas POST pool/dataset -d "$(jq -n --arg name "$1" '{name: $name, share_type: "GENERIC"}')" > /dev/null
}

ensure_nfs_share() {
  local share
  share=$(nas GET "sharing/nfs?path=$(uri "$1")" | jq -c 'first(.[]) // empty')
  if [ -z "$share" ]; then
    echo "nas: sharing $1 with the cluster nodes $NFS_CLIENTS"
    nas POST sharing/nfs -d "$(jq -n --arg path "$1" --argjson clients "$NFS_CLIENTS" \
      '{path: $path, networks: $clients, hosts: [], maproot_user: "root", maproot_group: "root"}')" > /dev/null
  elif ! jq -e --argjson clients "$NFS_CLIENTS" '(.networks | sort) == $clients and .hosts == []' <<< "$share" > /dev/null; then
    echo "nas: limiting $1 to the cluster nodes $NFS_CLIENTS"
    nas PUT "sharing/nfs/id/$(jq -r .id <<< "$share")" -d "$(jq -n --argjson clients "$NFS_CLIENTS" \
      '{networks: $clients, hosts: []}')" > /dev/null
  fi
}

storj_credential() {
  nas GET cloudsync/credentials | jq -er 'first(.[] | select(.provider.type == "STORJ_IX") | .id)'
}

ensure_storj_backup() {
  local path="$1" bucket="$2" folder="$3" hour="$4" dow="$5" keep="$6"
  nas GET "cloud_backup?path=$(uri "$path")" | jq -e 'any(.[]; .snapshot)' > /dev/null && return
  echo "nas: backing up $path to Storj $bucket:$folder"
  nas POST cloud_backup -d "$(jq -n \
    --arg path "$path" --arg bucket "$bucket" --arg folder "$folder" \
    --arg hour "$hour" --arg dow "$dow" --argjson keep "$keep" \
    --argjson credential "$STORJ_CREDENTIAL" --arg password "$TRUECLOUD_PASSWORD" \
    '{
      description: ("Backup " + ($path | ltrimstr("/mnt/"))),
      path: $path,
      credentials: $credential,
      attributes: {bucket: $bucket, folder: $folder},
      schedule: {minute: "0", hour: $hour, dom: "*", month: "*", dow: $dow},
      keep_last: $keep,
      password: $password,
      snapshot: true,
      enabled: true
    }')" > /dev/null
}

disable_backups_without_snapshots() {
  nas GET "cloud_backup?path=$(uri "$1")" | jq -r '.[] | select(.enabled and (.snapshot | not)) | .id' |
    while read -r id; do
      echo "nas: disabling backup task $id of $1; its leaf datasets are backed up with snapshots now"
      nas PUT "cloud_backup/id/$id" -d '{"enabled": false}' > /dev/null
    done
}

leaf_datasets() {
  nas GET "pool/dataset/id/$(uri "$1")" |
    jq -r '.. | objects | select(has("children") and (.children | length == 0) and .type == "FILESYSTEM") | .name'
}

ensure_snapshot_task() {
  local dataset="$1" recursive="$2" exclude="$3" schema="$4" days="$5" hour="$6"
  nas GET "pool/snapshottask?dataset=$(uri "$dataset")" |
    jq -e --arg schema "$schema" 'any(.[]; .naming_schema == $schema)' > /dev/null && return
  echo "nas: snapshotting $dataset ($schema, kept $days days)"
  nas POST pool/snapshottask -d "$(jq -n \
    --arg dataset "$dataset" --argjson recursive "$recursive" --argjson exclude "$exclude" \
    --arg schema "$schema" --argjson days "$days" --arg hour "$hour" \
    '{
      dataset: $dataset,
      recursive: $recursive,
      exclude: $exclude,
      naming_schema: $schema,
      lifetime_value: $days,
      lifetime_unit: "DAY",
      schedule: {minute: "0", hour: $hour, dom: "*", month: "*", dow: "*"},
      allow_empty: false,
      enabled: true
    }')" > /dev/null
}

ensure_datasets() {
  ensure_dataset "$APPS_DATASET"
  for class in backed transient; do
    for dataset in block "block/$class" "block/$class/v" "block/$class/s"; do
      ensure_dataset "$K8S_DATASET/$dataset"
    done
  done
}

ensure_shares() {
  ensure_nfs_share "/mnt/$APPS_DATASET"
}

storj_folder() {
  echo "/${1#"$POOL/"}"
}

ensure_storj_backups() {
  ensure_storj_backup "/mnt/$APPS_DATASET" "$STORJ_BUCKET" "$(storj_folder "$APPS_DATASET")" 3 '*' 60
  for leaf in $(leaf_datasets "$SERVICE_DATASET"); do
    ensure_storj_backup "/mnt/$leaf" "$STORJ_BUCKET" "$(storj_folder "$leaf")" 2 sat 52
  done
  disable_backups_without_snapshots "/mnt/$SERVICE_DATASET"
}

ensure_snapshots() {
  ensure_snapshot_task "$APPS_DATASET" false '[]' 'hourly-%Y-%m-%d_%H-%M' 2 '*'
  ensure_snapshot_task "$APPS_DATASET" false '[]' 'daily-%Y-%m-%d_%H-%M' 14 0
  ensure_snapshot_task "$USER_DATASET" true "[\"$SCRATCH_DATASET\"]" 'daily-%Y-%m-%d_%H-%M' 14 0
  ensure_snapshot_task "$SERVICE_DATASET" true '[]' 'daily-%Y-%m-%d_%H-%M' 14 0
  ensure_snapshot_task "$S3_DATASET" false '[]' 'daily-%Y-%m-%d_%H-%M' 14 0
}

STORJ_CREDENTIAL=$(storj_credential)

ensure_datasets
ensure_shares
ensure_storj_backups
ensure_snapshots
echo "nas: ok"
