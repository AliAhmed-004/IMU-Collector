#!/usr/bin/env bash
# Pull IMU csv files off the Wear OS watch over wireless adb into ./data/.
# No IP typing: relies on adb mDNS auto-connect, which finds the watch by a
# stable service name that survives DHCP IP changes.
#
# One-time setup on the watch (Developer options > Wireless debugging):
#   1. Tap "Pair device with pairing code" -> note host:port and the 6-digit code
#   2. On this machine:  adb pair <host:port>   (enter the code)
# After that, this script finds and connects to the watch on its own, as long
# as the laptop and watch are on the same network.

set -euo pipefail

APP_ID="com.spudbyte.imu_collector"
REMOTE_DIR="/storage/emulated/0/Android/data/${APP_ID}/files/"
LOCAL_DIR="./data"

adb start-server >/dev/null 2>&1

# Return the transport_id of the first device in "device" state, if any.
# Addressing by transport_id (not serial) avoids trouble with the mDNS serial
# names, which contain spaces and can appear twice for one watch.
connected_transport() {
  adb devices -l | awk '
    / device / {
      for (i = 1; i <= NF; i++)
        if ($i ~ /^transport_id:/) { sub(/transport_id:/, "", $i); print $i; exit }
    }'
}

tid="$(connected_transport)"

# Not connected yet: give auto-connect a moment to settle, then re-check.
if [[ -z "$tid" ]]; then
  echo "No device connected yet, waiting for auto-connect..."
  sleep 2
  tid="$(connected_transport)"
fi

if [[ -z "$tid" ]]; then
  echo "ERROR: no watch found." >&2
  echo "Check: watch on same WiFi, Wireless debugging ON, paired once (see top of script)." >&2
  echo "Current devices:" >&2
  adb devices -l >&2 || true
  exit 1
fi

echo "Using device transport_id: $tid"
mkdir -p "$LOCAL_DIR"

# -a preserves timestamps; adb pull overwrites, so re-runs refresh files.
adb -t "$tid" pull -a "$REMOTE_DIR" "$LOCAL_DIR"

echo "Done. Files in ${LOCAL_DIR}/files/"
ls -1 "${LOCAL_DIR}/files/"*.csv 2>/dev/null | wc -l | xargs echo "csv count:"
