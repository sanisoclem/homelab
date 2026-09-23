#!/usr/bin/env bash
# Runs on the Proxmox host, not here. Shuts the guests down in reverse startup
# order, arms the RTC so the board powers itself back on, then halts.
#
# Install:  scp scripts/night-off.sh root@<host>:/usr/local/sbin/night-off
#           chmod +x /usr/local/sbin/night-off
set -euo pipefail

WAKE_AT="${WAKE_AT:-07:00}"          # local time the board should come back up
GUEST_TIMEOUT="${GUEST_TIMEOUT:-600}" # seconds to wait for every guest to stop
DRY_RUN="${DRY_RUN:-0}"

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }

run() {
  if [ "$DRY_RUN" = "1" ]; then log "DRY RUN: $*"; else "$@"; fi
}

# pve-guests already stops guests in reverse startup order on poweroff, but it
# gives us no say in the timeout and TrueNAS wants minutes to export its pools.
# Doing it explicitly means we know everything is down before the board dies.
running=$(qm list | awk '$3 == "running" { print $1 }')

if [ -n "$running" ]; then
  # Descending startup order: workers, then controlplane, then the NAS.
  ordered=$(for id in $running; do
    order=$(qm config "$id" | sed -n 's/^startup:.*order=\([0-9]*\).*/\1/p')
    printf '%s %s\n' "${order:-0}" "$id"
  done | sort -rn | awk '{ print $2 }')

  for id in $ordered; do
    name=$(qm config "$id" | sed -n 's/^name: //p')
    log "stopping $id ($name)"
    run qm shutdown "$id" --timeout "$GUEST_TIMEOUT" --forceStop 1
  done
fi

log "all guests stopped"

# One-shot alarm, so it has to be re-armed on every shutdown — which is exactly
# what this script does. -u because Proxmox keeps the RTC in UTC.
rtc_flag="-u"
timedatectl show --property=RTCInLocalTZ --value | grep -qi yes && rtc_flag="-l"

wake_epoch=$(date -d "tomorrow $WAKE_AT" +%s)
log "arming RTC wake for $(date -d "@$wake_epoch" '+%F %T %Z')"
run rtcwake -m no "$rtc_flag" -t "$wake_epoch"

log "powering off"
run poweroff
