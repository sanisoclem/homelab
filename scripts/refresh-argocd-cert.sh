#!/usr/bin/env bash
set -euo pipefail

expand() { printf '%s' "${1/#\~/$HOME}"; }

KUBECONFIG=$(expand "${TF_VAR_kubeconfig_path:?TF_VAR_kubeconfig_path is not set}")
export KUBECONFIG

port=18443
forward_pid=""
cleanup() { [ -n "$forward_pid" ] && kill "$forward_pid" 2> /dev/null || true; }
trap cleanup EXIT

fingerprint() { openssl x509 -noout -fingerprint -sha256 2> /dev/null | cut -d= -f2; }

echo "argocd cert: waiting for the certificate to be issued"
kubectl -n argocd wait --for=condition=Ready certificate/argocd-server-tls --timeout=15m > /dev/null

want=$(kubectl -n argocd get secret argocd-server-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | fingerprint)
if [ -z "$want" ]; then
  echo "argocd cert: argocd-server-tls holds no usable certificate" >&2
  exit 1
fi

kubectl -n argocd port-forward svc/argocd-server "$port:443" > /dev/null 2>&1 &
forward_pid=$!

served=""
for _ in $(seq 1 30); do
  served=$(timeout 5 openssl s_client -connect "127.0.0.1:$port" -servername argocd < /dev/null 2> /dev/null | fingerprint) || served=''
  [ -n "$served" ] && break
  sleep 1
done

if [ "$served" = "$want" ]; then
  echo "argocd cert: server is already serving the issued certificate"
  exit 0
fi

echo "argocd cert: server is serving a stale certificate, restarting it"
kubectl -n argocd rollout restart deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
