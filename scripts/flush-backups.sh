#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG="${TF_VAR_kubeconfig_path:?TF_VAR_kubeconfig_path is not set}"
export KUBECONFIG="${KUBECONFIG/#\~/$HOME}"

STAMP=$(date +%s)
LABEL=homelab/flush

start_volume_backups() {
  kubectl get replicationsources -A -o json |
    jq --arg stamp "$STAMP" --arg label "$LABEL" '{
      apiVersion: "v1",
      kind: "List",
      items: [.items[] | select(.metadata.labels[$label] == null) | {
        apiVersion,
        kind,
        metadata: {name: (.metadata.name + "-flush"), namespace: .metadata.namespace, labels: {($label): $stamp}},
        spec: (.spec | .trigger = {manual: $stamp})
      }]
    }' | kubectl apply -f -
}

start_database_backups() {
  kubectl get clusters.postgresql.cnpg.io -A -o json |
    jq --arg stamp "$STAMP" --arg label "$LABEL" '{
      apiVersion: "v1",
      kind: "List",
      items: [.items[] | {
        apiVersion: "postgresql.cnpg.io/v1",
        kind: "Backup",
        metadata: {name: (.metadata.name + "-flush-" + $stamp), namespace: .metadata.namespace, labels: {($label): $stamp}},
        spec: {cluster: {name: .metadata.name}, method: "plugin", pluginConfiguration: {name: "barman-cloud.cloudnative-pg.io"}}
      }]
    }' | kubectl apply -f -
}

flushing() {
  [ -n "$(kubectl get "$1" -A -l "$LABEL=$STAMP" -o name)" ]
}

wait_for_backups() {
  if flushing replicationsources; then
    kubectl wait replicationsources -A -l "$LABEL=$STAMP" \
      --for=jsonpath='{.status.lastManualSync}'="$STAMP" --timeout=60m
  fi
  if flushing backups.postgresql.cnpg.io; then
    kubectl wait backups.postgresql.cnpg.io -A -l "$LABEL=$STAMP" \
      --for=jsonpath='{.status.phase}'=completed --timeout=60m
  fi
}

remove_flush_sources() {
  kubectl delete replicationsources -A -l "$LABEL=$STAMP"
}

echo "==> Backing up every block-backed volume and database one last time"
start_volume_backups
start_database_backups
wait_for_backups
remove_flush_sources
