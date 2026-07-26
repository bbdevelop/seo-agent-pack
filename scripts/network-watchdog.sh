#!/usr/bin/env bash
# Network watchdog for the wildscout.org cron schedule. Runs every 5 minutes.
#
# Pings the gateway; on two consecutive misses, bounces wlan0; if that doesn't restore
# connectivity, restarts connman (the actual manager of wlan0 on this box -- confirmed via
# `connmanctl`/`pgrep connmand`, NOT ifupdown/networking, which has no wlan0 stanza and would
# be a no-op here). Belt-and-suspenders behind the TLP wifi-powersave-off and
# fwlps=0/ips=0/swlps=0 modprobe fix already applied for the RTL8723BE's known idle drop-outs.
#
# Silent on a healthy network: nothing is logged unless a recovery step actually runs, so the
# log file answers "did this ever fire" at a glance. No Telegram alert by design -- an alert
# needs the network that's down.
set -uo pipefail

export PATH="/sbin:/usr/sbin:/usr/local/bin:/usr/bin:/bin"

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY="192.168.0.1"
IFACE="wlan0"
TODAY="$(date +%F)"
LOG_FILE="$PACK_DIR/logs/${TODAY}-network-watchdog.log"
LOCK_FILE="/tmp/wildscout-org-network-watchdog.lock"

mkdir -p "$PACK_DIR/logs"

log() {
  echo "$(date '+%F %T') | network-watchdog | $1" >> "$LOG_FILE"
}

ping_ok() {
  ping -c 1 -W 3 "$GATEWAY" > /dev/null 2>&1
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "skipped: previous watchdog run still in progress (lock held)"
  exit 0
fi

ping_ok && exit 0

# First miss alone is not enough to act on -- could be a single dropped packet.
sleep 5
ping_ok && exit 0

# Two consecutive misses: start recovery.
log "gateway ${GATEWAY} unreachable twice in a row, bouncing ${IFACE}"
ip link set "$IFACE" down
sleep 3
ip link set "$IFACE" up
sleep 10

ping_ok && { log "${IFACE} bounce restored connectivity"; exit 0; }

log "${IFACE} bounce did not restore connectivity, restarting connman"
service connman restart >> "$LOG_FILE" 2>&1
sleep 10

if ping_ok; then
  log "connman restart restored connectivity"
else
  log "connman restart did not restore connectivity, still unreachable"
fi
