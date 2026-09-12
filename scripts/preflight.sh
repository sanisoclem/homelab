#!/usr/bin/env bash
set -euo pipefail

missing=()

for tool in tofu kubectl helm talosctl openssl python3; do
  command -v "$tool" >/dev/null || missing+=("$tool is not on PATH")
done

[ -f .env ] || missing+=(".env not found")

require() {
  local name="$1"
  [ -n "${!name:-}" ] || missing+=("$name is unset in .env")
}

for name in TF_VAR_proxmox_endpoint TF_VAR_proxmox_node TF_VAR_proxmox_api_token \
  TF_VAR_vm_datastore_id TF_VAR_cloudflare_api_token TF_VAR_controlplane_vip; do
  require "$name"
done


if [ -n "${TF_VAR_proxmox_endpoint:-}" ] && [ -n "${TF_VAR_proxmox_api_token:-}" ]; then
  case "${TF_VAR_proxmox_api_token}" in
    *@*!*=*) ;;
    *) missing+=("TF_VAR_proxmox_api_token is not user@realm!tokenid=uuid; Proxmox prints the id and the value separately and both are needed") ;;
  esac

  status=$(curl -sS -o /tmp/pve-probe.$$ -w '%{http_code}' --max-time 10 \
    ${TF_VAR_proxmox_insecure:+-k} \
    -H "Authorization: PVEAPIToken=${TF_VAR_proxmox_api_token}" \
    "${TF_VAR_proxmox_endpoint%/}/api2/json/nodes/${TF_VAR_proxmox_node}/storage" 2>/dev/null || echo 000)
  storages=$(cat /tmp/pve-probe.$$ 2>/dev/null); rm -f /tmp/pve-probe.$$

  if [ "$status" = 000 ]; then
    missing+=("no response from ${TF_VAR_proxmox_endpoint} (dns, firewall or the wrong port)")
  elif [ "$status" = 401 ]; then
    missing+=("Proxmox rejected the token (401): check the id, the value, and that the token is not expired")
  elif [ "$status" = 403 ]; then
    missing+=("Proxmox accepted the token but denied it (403): it needs Datastore.Audit on / or --privsep 0")
  elif [ "$status" = 500 ] || [ "$status" = 596 ]; then
    missing+=("Proxmox returned $status for node '${TF_VAR_proxmox_node}': is that the right node name?")
  elif [ "$status" != 200 ]; then
    missing+=("Proxmox API returned HTTP $status")
  else
    check_content() {
      local store="$1" content="$2"
      printf '%s' "$storages" | STORE="$store" CONTENT="$content" python3 -c '
import json, os, sys
store, content = os.environ["STORE"], os.environ["CONTENT"]
entries = json.load(sys.stdin)["data"]
match = next((e for e in entries if e["storage"] == store), None)
if match is None:
    sys.exit(f"datastore {store!r} does not exist on this node")
if content not in (match.get("content") or "").split(","):
    sys.exit(f"datastore {store!r} does not have the {content!r} content type enabled")
' 2>&1
    }

    for pair in "${TF_VAR_image_datastore_id:-local}:iso" \
      "${TF_VAR_snippet_datastore_id:-local}:snippets" \
      "${TF_VAR_vm_datastore_id}:images"; do
      if problem=$(check_content "${pair%:*}" "${pair##*:}"); then :; else
        missing+=("$problem")
      fi
    done
  fi
fi

if [ -n "${TF_VAR_proxmox_endpoint:-}" ]; then
  host="${TF_VAR_proxmox_endpoint#*://}"
  host="${host%%:*}"
  ssh_user="${TF_VAR_proxmox_ssh_username:-root}"
  ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
  [ -n "${TF_VAR_proxmox_ssh_private_key:-}" ] && ssh_opts+=(-i "${TF_VAR_proxmox_ssh_private_key/#\~/$HOME}")

  ssh "${ssh_opts[@]}" "$ssh_user@$host" true >/dev/null 2>&1 ||
    missing+=("cannot ssh to $ssh_user@$host; the provider uploads machine configs over ssh, not the API")
fi

if [ -n "${TF_VAR_nas_host:-}" ]; then
  timeout 3 bash -c "</dev/tcp/${TF_VAR_nas_host}/443" 2>/dev/null ||
    missing+=("the TrueNAS API at ${TF_VAR_nas_host}:443 is not answering; start the NAS before the cluster looks for its volumes")
fi

for path in "${TF_VAR_platform_path:-}" "${TF_VAR_hempire_path:-}" "${TF_VAR_home_path:-}"; do
  [ -n "$path" ] || continue
  [ -d "bootstrap/$path" ] || missing+=("no checkout at bootstrap/$path")
done

if [ ${#missing[@]} -gt 0 ]; then
  printf 'preflight failed:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  printf '\nSee the Prerequisites section of the README.\n' >&2
  exit 1
fi

echo "preflight: ok"
