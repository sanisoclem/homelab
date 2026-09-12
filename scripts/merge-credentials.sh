#!/usr/bin/env bash
set -euo pipefail

expand() { printf '%s' "${1/#\~/$HOME}"; }

merge_kubeconfig() {
  local source destination inputs merged current
  source=$(expand "${TF_VAR_kubeconfig_path:?TF_VAR_kubeconfig_path is not set}")
  destination="$HOME/.kube/config"

  if [ ! -f "$source" ]; then
    echo "credentials: no kubeconfig at $source" >&2
    return 1
  fi

  mkdir -p "$(dirname "$destination")"
  inputs="$source"
  current=""
  if [ -f "$destination" ]; then
    cp "$destination" "$destination.bak"
    current=$(kubectl --kubeconfig "$destination" config current-context 2> /dev/null || true)
    inputs="$source:$destination"
  fi

  merged=$(mktemp)
  KUBECONFIG="$inputs" kubectl config view --flatten > "$merged"
  if [ -n "$current" ]; then
    kubectl --kubeconfig "$merged" config use-context "$current" > /dev/null 2>&1 || true
  fi
  install -m 600 "$merged" "$destination"
  rm -f "$merged"
  echo "credentials: merged into $destination"
}

merge_talosconfig() {
  local source
  source=$(expand "${TF_VAR_talosconfig_path:-}")
  [ -n "$source" ] && [ -f "$source" ] || return 0

  if ! command -v talosctl > /dev/null; then
    echo "credentials: talosctl not on PATH, leaving $source unmerged" >&2
    return 0
  fi

  talosctl config merge "$source"
  echo "credentials: merged into $HOME/.talos/config"
}

merge_kubeconfig
merge_talosconfig
