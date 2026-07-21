#!/usr/bin/env bash
# Assemble the self-contained setup.sh from scripts/setup.sh.in + lib/ + portal/
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$here/lib"
tmp_lib="$(mktemp)"; tmp_portal="$(mktemp)"
for f in switch-mode.sh wl-refresh.py wl-refresh.sh recon-capture-loop.sh recondump.py; do
  m="SAI_$(echo "$f" | tr '.-' '__')_EOF"
  echo "cat > /sd/bot/$f <<'$m'"
  cat "$LIB/$f"
  echo "$m"
  echo "chmod +x /sd/bot/$f 2>/dev/null"
done > "$tmp_lib"
{ echo "cat > \"\$PDIR/index.php\" <<'SAI_PORTAL_EOF'"; cat "$here/portal/index.php.template"; echo "SAI_PORTAL_EOF"; } > "$tmp_portal"
awk -v lib="$tmp_lib" -v portal="$tmp_portal" '
  /__EMBED_LIB__/    { while((getline l < lib) > 0) print l; next }
  /__EMBED_PORTAL__/ { while((getline l < portal) > 0) print l; next }
  { print }
' "$here/scripts/setup.sh.in" > "$here/setup.sh"
rm -f "$tmp_lib" "$tmp_portal"
echo "built setup.sh ($(wc -l < "$here/setup.sh") lines)"
