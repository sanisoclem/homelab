NAS="${TF_VAR_nas_host:?TF_VAR_nas_host is not set}"
NAS_API_KEY="${TF_VAR_truenas_api_key:?TF_VAR_truenas_api_key is not set}"
K8S_DATASET="${TF_VAR_nas_dataset:?TF_VAR_nas_dataset is not set}"
POOL="${K8S_DATASET%%/*}"
APPS_DATASET="$K8S_DATASET/apps"

nas() {
  local method="$1" path="$2"
  shift 2
  curl -sSk --fail-with-body --max-time 120 -X "$method" \
    -H "Authorization: Bearer $NAS_API_KEY" -H 'Content-Type: application/json' \
    "https://$NAS/api/v2.0/$path" "$@"
}

uri() { jq -rn --arg value "$1" '$value | @uri'; }
