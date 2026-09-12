#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GITOPS_DIR="${GITOPS_DIR:-$(cd "$INFRA_DIR/bootstrap/${TF_VAR_hempire_path:-../gitops}" && pwd)}"
ENV_FILE="$INFRA_DIR/.env"

if [ -n "${TF_VAR_kubeconfig_path:-}" ]; then
  export KUBECONFIG="${TF_VAR_kubeconfig_path/#\~/$HOME}"
fi

echo "Waiting for Argo CD to bring Zitadel up..."
for _ in $(seq 1 120); do
  kubectl -n zitadel get deploy zitadel >/dev/null 2>&1 && break
  sleep 5
done

settled() {
  kubectl -n zitadel get deploy zitadel -o json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
spec, status = d["spec"], d.get("status", {})
want = spec.get("replicas", 1)
sys.exit(0 if (
    status.get("observedGeneration") == d["metadata"]["generation"]
    and status.get("updatedReplicas") == want
    and status.get("availableReplicas") == want
    and status.get("replicas") == want
) else 1)
'
}

echo "Waiting for the Zitadel deployment to settle..."
stable=0
for _ in $(seq 1 240); do
  if settled; then
    stable=$((stable + 1))
    [ "$stable" -ge 3 ] && break
  else
    stable=0
  fi
  sleep 5
done
if [ "$stable" -lt 3 ]; then
  echo "zitadel deployment never settled" >&2
  kubectl -n zitadel get pods >&2
  exit 1
fi

ZITADEL_URL=$(sed -n 's/^[[:space:]]*ZITADEL_URL:[[:space:]]*\(\S*\).*/\1/p' \
  "$GITOPS_DIR/config/cluster-config.yaml" | head -1 | tr -d '"'"'"'"')
if [ -z "$ZITADEL_URL" ]; then
  echo "no ZITADEL_URL in $GITOPS_DIR/config/cluster-config.yaml" >&2
  exit 1
fi

echo "Waiting for $ZITADEL_URL to answer..."
for _ in $(seq 1 60); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$ZITADEL_URL/debug/healthz" 2>/dev/null || echo 000)
  case "$code" in
    000) ;;
    *) break ;;
  esac
  sleep 5
done
if [ "$code" = 000 ]; then
  cat >&2 <<MSG
$ZITADEL_URL is not reachable.

Seeding goes through the public name, so this needs DNS, the gateway and a valid
certificate all working. Check:
  getent hosts ${ZITADEL_URL#https://}
  kubectl -n zitadel get certificate zitadel-tls
  kubectl get gateway -n nginx-gateway
MSG
  exit 1
fi

read_pat() {
  local pod value
  for _ in $(seq 1 60); do
    pod=$(kubectl -n zitadel get pod -l app=zitadel \
      --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$pod" ]; then
      value=$(kubectl -n zitadel exec "$pod" -c pat-reader -- cat /pat/token 2>/dev/null || true)
      if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
      fi
    fi
    sleep 5
  done
  return 1
}

token="${ZITADEL_PAT:-}"
if [ -z "$token" ]; then
  token=$(read_pat || true)
fi
if [ -z "$token" ]; then
  cat >&2 <<'MSG'
No Zitadel credential available.
MSG
  exit 1
fi

seed_log=$(mktemp)
ZITADEL_TOKEN="$token" python3 "$SCRIPT_DIR/seed-zitadel.py" \
  --url "$ZITADEL_URL" \
  --gitops-dir "$GITOPS_DIR" \
  --env-file "$ENV_FILE" | tee "$seed_log"

if grep -q '^seed: secrets updated' "$seed_log"; then
  echo
  echo "Client secrets changed — re-applying bootstrap so the cluster picks them up."
  (cd "$INFRA_DIR" && task bootstrap:apply TF_APPLY_ARGS=-auto-approve)
fi

rel="config/cluster-config.yaml"
if ! git -C "$GITOPS_DIR" diff --quiet -- "$rel"; then
  git -C "$GITOPS_DIR" --no-pager diff -- "$rel"
  cat >&2 <<MSG

$rel is updated 
MSG
fi
