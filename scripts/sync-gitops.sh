#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

resolve() {
  local path="${1:?}"
  (cd "$ROOT/bootstrap" && cd "$path" && pwd)
}

PLATFORM_DIR=$(resolve "${TF_VAR_platform_path:-../platform-gitops}")
HEMPIRE_DIR=$(resolve "${TF_VAR_hempire_path:-../gitops}")
HOME_DIR=$(resolve "${TF_VAR_home_path:-../home-gitops}")

echo "Reading cluster outputs..."
cluster_out=$(tofu -chdir="$ROOT/cluster" output -json)

CLUSTER_OUT="$cluster_out" \
  GITHUB_ORG="${GITHUB_ORG:?GITHUB_ORG is not set}" \
  PLATFORM_REPO_URL="${TF_VAR_platform_repo_url:?}" \
  HEMPIRE_REPO_URL="${TF_VAR_hempire_repo_url:?}" \
  HOME_REPO_URL="${TF_VAR_home_repo_url:?}" \
  python3 - "$PLATFORM_DIR" "$HEMPIRE_DIR" "$HOME_DIR" <<'PYEOF'
import json, os, re, sys

platform_dir, hempire_dir, home_dir = sys.argv[1:4]
cluster = {key: value['value'] for key, value in json.loads(os.environ['CLUSTER_OUT']).items()}

zone = cluster['dns_zone']

auth = {
    'DNS_ZONE':      zone,
    'ZITADEL_URL':   f'https://a.{zone}',
    'AUTH_JWKS_URI': f'https://a.{zone}/oauth/v2/keys',
}

platform = {
    **auth,
    'repoURL':           os.environ['PLATFORM_REPO_URL'],
    'hempireRepoURL':    os.environ['HEMPIRE_REPO_URL'],
    'homeRepoURL':       os.environ['HOME_REPO_URL'],
    'GATEWAY_IP':        cluster['gateway_ip'],
    'METALLB_POOL':      cluster['metallb_pool'],
    'GITHUB_ORG':        os.environ['GITHUB_ORG'],
    'LETSENCRYPT_EMAIL': cluster['letsencrypt_email'],
    'S3_ENDPOINT':       cluster['s3_endpoint'],
}


def patch(path, values):
    with open(path) as f:
        content = f.read()

    missing = [key for key in values
               if not re.search(rf'^\s+{re.escape(key)}:', content, re.MULTILINE)]
    if missing:
        sys.exit(f'{path} is missing keys: {", ".join(missing)}')

    for key, value in values.items():
        new = re.sub(rf'^(\s+{re.escape(key)}:).*$',
                     lambda m, v=value: f'{m.group(1)} {v}',
                     content, flags=re.MULTILINE)
        if new != content:
            print(f'  {os.path.basename(os.path.dirname(path))}: updated {key}')
        content = new

    with open(path, 'w') as f:
        f.write(content)


patch(f'{platform_dir}/config/cluster-config.yaml', platform)
for directory in (hempire_dir, home_dir):
    patch(f'{directory}/config/cluster-config.yaml', auth)
PYEOF

dirty=0
for dir in "$PLATFORM_DIR" "$HEMPIRE_DIR" "$HOME_DIR"; do
  git -C "$dir" diff --quiet -- config/cluster-config.yaml && continue
  dirty=1
  git -C "$dir" --no-pager diff -- config/cluster-config.yaml
done

if [ "$dirty" -eq 0 ]; then
  echo "No changes — every cluster-config is already up to date."
else
  cat >&2 <<'MSG'
Cluster configs have been updated. 
MSG
fi
