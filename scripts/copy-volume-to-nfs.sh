#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:?usage: copy-volume-to-nfs.sh NAMESPACE PVC SUBPATH}"
PVC="${2:?usage: copy-volume-to-nfs.sh NAMESPACE PVC SUBPATH}"
SUBPATH="${3:?usage: copy-volume-to-nfs.sh NAMESPACE PVC SUBPATH}"
NAS="${TF_VAR_nas_host:?TF_VAR_nas_host is not set}"
APPS_PATH="/mnt/${TF_VAR_nas_dataset:?TF_VAR_nas_dataset is not set}/apps"

KUBECONFIG="${TF_VAR_kubeconfig_path:?TF_VAR_kubeconfig_path is not set}"
export KUBECONFIG="${KUBECONFIG/#\~/$HOME}"

JOB="copy-$PVC-to-nfs"

node_using_pvc() {
  kubectl -n "$NAMESPACE" get pods -o json |
    jq -r --arg pvc "$PVC" 'first(.items[] | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $pvc)) | .spec.nodeName) // ""'
}

copy() {
  kubectl apply -f - << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
  namespace: $NAMESPACE
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeName: $1
      securityContext:
        runAsUser: 0
      containers:
        - name: copy
          image: busybox:1.38
          command: ["/bin/sh", "-euc", "mkdir -p '/apps/$SUBPATH' && cp -a /volume/. '/apps/$SUBPATH/'"]
          volumeMounts:
            - name: volume
              mountPath: /volume
              readOnly: true
            - name: apps
              mountPath: /apps
      volumes:
        - name: volume
          persistentVolumeClaim:
            claimName: $PVC
            readOnly: true
        - name: apps
          nfs:
            server: $NAS
            path: $APPS_PATH
EOF
  kubectl -n "$NAMESPACE" wait "job/$JOB" --for=condition=complete --timeout=60m
  kubectl -n "$NAMESPACE" delete "job/$JOB"
}

node=$(node_using_pvc)
[ -n "$node" ] || node=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
copy "$node"
echo "copy: $NAMESPACE/$PVC is in $APPS_PATH/$SUBPATH; push the manifest that mounts it"
