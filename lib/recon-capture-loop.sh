#!/bin/sh
# Alternating recon <-> passive handshake capture. STRICTLY one consumer of the
# monitor at a time, with waits for async scan completion + settle delays between
# phases (the churn of rapid start/stop is what wedged the device; long phases + clean
# handoffs avoid it). Args: $1 = recon seconds (default 300), $2 = capture seconds (default 900).
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
HCX=/sd/usr/sbin/hcxdumptool
OUT=/sd/handshakes; STATUS="$OUT/hcx-status.log"; LOG=/sd/bot/altloop.log
mkdir -p "$OUT"
SCAN=${1:-300}; CAP=${2:-900}
lg(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }
lg "=== altloop start (scan=${SCAN}s cap=${CAP}s) ==="
while true; do
  # ===== RECON phase (async run_scan, then wait for it to finish) =====
  lg "recon: run_scan ${SCAN}s"
  pineap /tmp/pineap.conf run_scan "$SCAN" 2 >/dev/null 2>&1
  W=0; LIM=$((SCAN+40))
  while [ "$W" -lt "$LIM" ]; do
    pineap /tmp/pineap.conf get_status 2>/dev/null | grep scanRunning | grep -q true || break
    sleep 5; W=$((W+5))
  done
  lg "recon: done (waited ${W}s)"
  # ===== transition -> capture: free the monitor, settle =====
  pineap /tmp/pineap.conf stop_scan >/dev/null 2>&1
  pineap /tmp/pineap.conf pause    >/dev/null 2>&1
  sleep 6
  # ===== CAPTURE phase: ONE long hcxdumptool window (no churn) =====
  TS=$(date +%Y%m%d_%H%M%S)
  lg "capture: hcx ${CAP}s -> cap_$TS.pcapng"
  "$HCX" -i wlan1mon -o "$OUT/cap_$TS.pcapng" -t 5 --disable_client_attacks --enable_status=3 >>"$STATUS" 2>&1 &
  HP=$!
  W=0
  while [ "$W" -lt "$CAP" ] && kill -0 "$HP" 2>/dev/null; do sleep 10; W=$((W+10)); done
  kill "$HP" 2>/dev/null; sleep 3; kill -9 "$HP" 2>/dev/null; sleep 6
  lg "capture: done"
  # ===== transition -> recon: resume hop, settle =====
  pineap /tmp/pineap.conf unpause >/dev/null 2>&1
  sleep 4
  # housekeeping
  [ -f "$OUT/cap_$TS.pcapng" ] && [ "$(wc -c < "$OUT/cap_$TS.pcapng")" -lt 2000 ] && rm -f "$OUT/cap_$TS.pcapng"
  ls -t "$OUT"/cap_*.pcapng 2>/dev/null | tail -n +400 | xargs rm -f 2>/dev/null
  tail -c 300000 "$STATUS" > "$STATUS.t" 2>/dev/null && mv "$STATUS.t" "$STATUS"
done
