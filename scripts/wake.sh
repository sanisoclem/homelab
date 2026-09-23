#!/usr/bin/env bash
# Wake the Proxmox host by magic packet. Run from anywhere on the node VLAN, or
# over ssh on the UDM:  ssh root@<udm> 'bash -s' < scripts/wake.sh
#
#   ./scripts/wake.sh AA:BB:CC:DD:EE:FF [host-ip]
#
# Sent unicast rather than broadcast on purpose: bash's /dev/udp cannot set
# SO_BROADCAST, and a sleeping NIC wakes on the payload either way. The catch is
# that the host's ARP entry expires while it is off, so the sender needs a
# permanent one — see the note at the bottom.
set -euo pipefail

MAC="${1:?usage: wake.sh <mac> [host-ip]}"
DEST="${2:-10.11.7.255}"
PORT="${PORT:-9}"

hex=$(printf '%s' "$MAC" | tr -d ':-' | tr 'A-F' 'a-f')
[ "${#hex}" -eq 12 ] || { echo "not a mac address: $MAC" >&2; exit 1; }

# 6 x 0xff, then the mac 16 times over
packet=$(printf '\\xff%.0s' 1 2 3 4 5 6)
for _ in $(seq 16); do
  packet="$packet$(printf '%s' "$hex" | sed 's/../\\x&/g')"
done

if command -v wakeonlan >/dev/null; then
  exec wakeonlan -i "$DEST" "$MAC"
elif command -v etherwake >/dev/null; then
  exec etherwake "$MAC"
fi

# shellcheck disable=SC2059
printf "$packet" > "/dev/udp/$DEST/$PORT"
echo "magic packet sent to $DEST:$PORT for $MAC"

# On the UDM, pin the ARP entry once so unicast keeps working while the host is
# off (re-apply after a firmware update, it does not persist):
#
#   ip neigh replace <host-ip> lladdr <mac> nud permanent dev <br-iface>
