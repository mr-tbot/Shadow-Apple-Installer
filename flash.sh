#!/usr/bin/env sh
# =============================================================================
#  Shadow-Apple-Installer  ·  flash.sh
#  Flash a GL.iNet AR300M-class router into the WiFi Pineapple Cloner over SSH.
#
#  RUN ON YOUR COMPUTER (Git Bash on Windows, or Linux/macOS terminal).
#  The router may be on stock GL.iNet firmware OR OpenWrt — both expose sysupgrade.
#
#  Needs on your machine: sh, curl OR wget, and ONE SSH transport:
#     - PuTTY plink/pscp (recommended on Windows), or
#     - OpenSSH ssh + sshpass, or plain ssh (you'll type the password per step).
#
#  ⚠ DESTRUCTIVE — the router is wiped. AR300M units recover via uboot
#     (hold reset while powering on -> http://192.168.1.1, NIC 192.168.1.2/24).
#     Authorized security testing only.
# =============================================================================
set -u
BUILDS="https://gitlab.com/xchwarze/wifi-pineapple-cloner-builds/-/raw/main/releases"
UPGRADES="https://gitlab.com/xchwarze/wifi-pineapple-cloner-builds/-/raw/main/upgrades.json"

say(){ printf '%s\n' "$*"; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
ask(){ _d="${2:-}"; if [ -n "$_d" ]; then printf '%s [%s]: ' "$1" "$_d" >&2; else printf '%s: ' "$1" >&2; fi
       IFS= read -r _a || true; [ -z "$_a" ] && _a="$_d"; printf '%s' "$_a"; }
askpw(){ printf '%s: ' "$1" >&2; stty -echo 2>/dev/null || true; IFS= read -r _a || true
         stty echo 2>/dev/null || true; printf '\n' >&2; printf '%s' "$_a"; }
fetch(){ if have curl; then curl -fsSL "$1"; elif have wget; then wget -qO- "$1"; else die "need curl or wget"; fi; }
fetchfile(){ if have curl; then curl -fsSL "$1" -o "$2"; elif have wget; then wget -qO "$2" "$1"; else die "need curl or wget"; fi; }
sha256(){ if have sha256sum; then sha256sum "$1" | awk '{print $1}'
          elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'; else die "need sha256sum/shasum"; fi; }

PLINK=""
for c in plink "/c/Program Files/PuTTY/plink.exe" "/c/Program Files (x86)/PuTTY/plink.exe"; do
  command -v "$c" >/dev/null 2>&1 && { PLINK="$c"; break; }
done
[ -n "$PLINK" ] || have ssh || die "no SSH client found (install PuTTY or OpenSSH)."

say "=== Shadow-Apple-Installer :: flash ==="
IP=$(ask "Router IP" "192.168.8.1")
SUSER=$(ask "SSH user" "root")
PW=$(askpw "SSH password for ${SUSER}@${IP}")
say ""
say "Cloner device key = your router model. Common: gl-ar300m (AR300M16/Shadow),"
say "gl-ar750s, gl-mt300n-v2, archer-c7-v5, wndr3800 …  (full list in the cloner-builds repo)."
DEV=$(ask "Cloner device key" "gl-ar300m")

run(){ if [ -n "$PLINK" ]; then "$PLINK" -batch -ssh -pw "$PW" "${SUSER}@${IP}" "$1"
       elif have sshpass; then sshpass -p "$PW" ssh -o StrictHostKeyChecking=accept-new "${SUSER}@${IP}" "$1"
       else ssh -o StrictHostKeyChecking=accept-new "${SUSER}@${IP}" "$1"; fi; }
putfile(){ if [ -n "$PLINK" ]; then "$PLINK" -batch -ssh -pw "$PW" "${SUSER}@${IP}" "cat > $2" < "$1"
           elif have sshpass; then sshpass -p "$PW" ssh -o StrictHostKeyChecking=accept-new "${SUSER}@${IP}" "cat > $2" < "$1"
           else ssh -o StrictHostKeyChecking=accept-new "${SUSER}@${IP}" "cat > $2" < "$1"; fi; }

[ -n "$PLINK" ] && printf 'y\n' | "$PLINK" -ssh -pw "$PW" "${SUSER}@${IP}" "exit" >/dev/null 2>&1

say ""; say "Probing router…"
run "uname -a; echo BOARD=\$(cat /tmp/sysinfo/board_name 2>/dev/null)" \
  || die "cannot SSH to ${SUSER}@${IP} — check IP / password / transport."

say ""; say "Resolving firmware for '$DEV'…"
JSON=$(fetch "$UPGRADES") || die "cannot fetch cloner manifest"
OBJ=$(printf '%s' "$JSON" | grep -o "\"${DEV}\":{[^}]*}") || true
[ -n "$OBJ" ] || die "device key '${DEV}' not found in the cloner manifest."
URL=$(printf '%s' "$OBJ" | grep -o '"upgradeUrl":"[^"]*"' | sed 's/.*"upgradeUrl":"//;s/"$//;s#\\/#/#g')
CK=$(printf '%s' "$OBJ" | grep -o '"checksum":"[0-9a-f]\{64\}"' | sed 's/.*"checksum":"//;s/"//')
[ -n "$URL" ] || URL="${BUILDS}/${DEV}-universal-sysupgrade.bin"
say "Image : $URL"
say "SHA256: ${CK:-<none published>}"

TMP="${TMPDIR:-/tmp}/shadow-apple-${DEV}.bin"
say "Downloading…"; fetchfile "$URL" "$TMP" || die "download failed"
GOT=$(sha256 "$TMP")
if [ -z "$CK" ]; then
  say "[!] No published checksum for '$DEV' — this image cannot be integrity-verified."
  A=$(ask "Flash it UNVERIFIED anyway? Type 'UNVERIFIED' to allow" "")
  [ "$A" = "UNVERIFIED" ] || die "aborted — refusing to flash an unverified image over sysupgrade."
elif [ "$GOT" != "$CK" ]; then
  die "SHA256 mismatch! got=$GOT want=$CK"
fi
say "Downloaded $(wc -c < "$TMP") bytes, sha256=$GOT  $([ -n "$CK" ] && echo '✓ verified' || echo '(UNVERIFIED)')"

say ""
say "About to WIPE ${SUSER}@${IP} and flash the cloner. Irreversible (recover via uboot)."
C=$(ask "Type EXACTLY 'FLASH' to proceed" "")
[ "$C" = "FLASH" ] || die "aborted."

say "Staging image (streamed — no SFTP needed)…"
putfile "$TMP" "/tmp/cloner.bin" || die "transfer failed"
RGOT=$(run "sha256sum /tmp/cloner.bin | awk '{print \$1}'")
say "on-device sha256=$RGOT"
[ -z "$CK" ] || [ "$RGOT" = "$CK" ] || die "on-device checksum mismatch — NOT flashing."

say "Flashing (sysupgrade -F -n). SSH will drop; the device reboots for ~3 minutes."
run "sysupgrade -F -n /tmp/cloner.bin" 2>&1 || true
say ""
say "Done. The cloner comes up at http://172.16.42.1:1471/ (your NIC re-DHCPs into 172.16.42.x)."
say "Next: run setup.sh on the device —"
say "   cat setup.sh | ssh root@172.16.42.1 \"cat > /tmp/setup.sh\""
say "   ssh -t root@172.16.42.1 \"sh /tmp/setup.sh\""
