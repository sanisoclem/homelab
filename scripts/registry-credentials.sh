#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="$root/bootstrap/registry.auto.tfvars"
host="${REGISTRY_HOST:-}"
repo="${HEMPIRE_REPO:-${GITHUB_ORG:-}/hempire}"

[ -n "$host" ] || { echo "REGISTRY_HOST is unset in .env" >&2; exit 1; }
[ "$repo" != "/hempire" ] || { echo "GITHUB_ORG is unset in .env" >&2; exit 1; }

for tool in htpasswd openssl gh; do
  command -v "$tool" >/dev/null || { echo "$tool is not on PATH" >&2; exit 1; }
done

read_var() {
  [ -f "$tfvars" ] || return 0
  sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"$/\1/p" "$tfvars" | tail -1
}

write_tfvars() {
  umask 077
  cat > "$tfvars" <<TFVARS
registry_host                 = "$host"
registry_ci_password_hash     = "$1"
registry_puller_password      = "$2"
registry_puller_password_hash = "$3"
TFVARS
}

ci_hash=$(read_var registry_ci_password_hash)
puller_password=$(read_var registry_puller_password)
puller_hash=$(read_var registry_puller_password_hash)

if [ -n "$ci_hash" ] && [ -n "$puller_password" ] && [ -n "$puller_hash" ]; then
  write_tfvars "$ci_hash" "$puller_password" "$puller_hash"
  echo "registry credentials already set; reusing them"
  if ! gh secret list --repo "$repo" 2>/dev/null | grep -q '^REGISTRY_TOKEN'; then
    echo "REGISTRY_TOKEN is missing on $repo and the ci password is not stored anywhere." >&2
    echo "Delete the registry_ci_password_hash line from bootstrap/registry.auto.tfvars and re-run to mint a new one." >&2
    exit 1
  fi
  exit 0
fi

[ -n "$puller_password" ] || puller_password=$(openssl rand -hex 32)
[ -n "$puller_hash" ] || puller_hash=$(htpasswd -nbB puller "$puller_password" | cut -d: -f2-)

ci_password=$(openssl rand -hex 32)
ci_hash=$(htpasswd -nbB ci "$ci_password" | cut -d: -f2-)

write_tfvars "$ci_hash" "$puller_password" "$puller_hash"
printf '%s' "$ci_password" | gh secret set REGISTRY_TOKEN --repo "$repo"

echo "minted the registry credentials and set REGISTRY_TOKEN on $repo"
