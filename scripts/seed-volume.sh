#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:?usage: seed-volume.sh NAMESPACE SOURCE_PVC TARGET_PVC}"
SOURCE="${2:?usage: seed-volume.sh NAMESPACE SOURCE_PVC TARGET_PVC}"
TARGET="${3:?usage: seed-volume.sh NAMESPACE SOURCE_PVC TARGET_PVC}"
S3_ENDPOINT="${TF_VAR_s3_endpoint:?TF_VAR_s3_endpoint is not set}"

KUBECONFIG="${TF_VAR_kubeconfig_path:?TF_VAR_kubeconfig_path is not set}"
export KUBECONFIG="${KUBECONFIG/#\~/$HOME}"

STAMP=$(date +%s)
SEED="$TARGET-seed"

allow_privileged_movers() {
  kubectl annotate namespace "$NAMESPACE" volsync.backube/privileged-movers=true --overwrite
}

write_repository_secret() {
  kubectl -n secrets get secret volsync-restic -o json |
    jq --arg namespace "$NAMESPACE" --arg name "$SEED" \
      --arg repository "s3:$S3_ENDPOINT/backups/volsync/$NAMESPACE/$TARGET" '{
        apiVersion: "v1",
        kind: "Secret",
        metadata: {name: $name, namespace: $namespace},
        data: (.data + {RESTIC_REPOSITORY: ($repository | @base64)})
      }' | kubectl apply -f -
}

back_up_source() {
  kubectl apply -f - << EOF
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: $SEED
  namespace: $NAMESPACE
spec:
  sourcePVC: $SOURCE
  trigger:
    manual: "$STAMP"
  restic:
    repository: $SEED
    copyMethod: Direct
    cacheStorageClassName: block-transient
EOF
  kubectl -n "$NAMESPACE" wait "replicationsource/$SEED" \
    --for=jsonpath='{.status.lastManualSync}'="$STAMP" --timeout=60m
}

remove_seed() {
  kubectl -n "$NAMESPACE" delete "replicationsource/$SEED" "secret/$SEED"
}

allow_privileged_movers
write_repository_secret
back_up_source
remove_seed
echo "seed: $NAMESPACE/$TARGET will restore from $NAMESPACE/$SOURCE; push the manifest that switches to $TARGET"
