#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="$root/bootstrap/registry.auto.tfvars"
host="${REGISTRY_HOST:-}"
repo="${HEMPIRE_REPO:-}"

[ -n "$host" ] || { echo "REGISTRY_HOST is unset in .env" >&2; exit 1; }
[ -n "$repo" ] || { echo "HEMPIRE_REPO is unset in .env; it is the owner and name of the app repository, such as Saline-Pty-Ltd/hempire" >&2; exit 1; }

for tool in htpasswd openssl gh; do
  command -v "$tool" >/dev/null || { echo "$tool is not on PATH" >&2; exit 1; }
done

gh api "repos/$repo" --jq .full_name > /dev/null 2>&1 ||
  { echo "cannot reach $repo as the account gh is logged in to; check HEMPIRE_REPO and \`gh auth status\`" >&2; exit 1; }

read_var() {
  [ -f "$tfvars" ] || return 0
  sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"$/\1/p" "$tfvars" | tail -1
}

bcrypt() { htpasswd -nbB "$1" "$2" | cut -d: -f2-; }

puller_password=$(read_var registry_puller_password)
puller_hash=$(read_var registry_puller_password_hash)
ci_hash=$(read_var registry_ci_password_hash)

[ -n "$puller_password" ] || puller_password=$(openssl rand -hex 32)
[ -n "$puller_hash" ] || puller_hash=$(bcrypt puller "$puller_password")

token_present=false
gh secret list --repo "$repo" --json name --jq '.[].name' 2>/dev/null |
  grep -qx REGISTRY_TOKEN && token_present=true

if [ -z "$ci_hash" ] || [ "$token_present" = false ]; then
  ci_password=$(openssl rand -hex 32)
  ci_hash=$(bcrypt ci "$ci_password")
  printf '%s' "$ci_password" | gh secret set REGISTRY_TOKEN --repo "$repo"
  outcome="minted a ci password and set REGISTRY_TOKEN on $repo"
else
  outcome="reusing the credentials in bootstrap/registry.auto.tfvars"
fi

umask 077
cat > "$tfvars" <<TFVARS
registry_host                 = "$host"
registry_ci_password_hash     = "$ci_hash"
registry_puller_password      = "$puller_password"
registry_puller_password_hash = "$puller_hash"
TFVARS

echo "$outcome"
