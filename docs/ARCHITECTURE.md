# Architecture

## Two-step install

1. **`flash.sh`** (your computer) → flashes the router into xchwarze's
   *WiFi Pineapple Cloner* over SSH (`sysupgrade -F -n`, checksum-verified).
2. **`setup.sh`** (the device) → interactive configuration of everything below.

`setup.sh` is **self-contained**: it embeds the device scripts (`lib/`) and the
portal template (`portal/`) and writes them to `/sd/bot/` and the active portal.
The `lib/` and `portal/` files in this repo are the readable source; run
`scripts/build.sh` to regenerate `setup.sh` after editing them.

## On-device layout

```
/sd/bot/
  switch-mode.sh         hardware-switch daemon (recon <-> deauth+capture)
  recon-capture-loop.sh  time-based alternation (auto mode)
  recon-only.sh          recon-only loop (recon mode)
  wl-refresh.py / .sh    build protected-BSSID lists from protect-ssids.conf
  recondump.py           recon.db summary for reports
  protect-ssids.conf     your protected SSID names (prefix with * supported)
  hcx-protect.list       generated: hcxdumptool --filterlist_ap (lowercase MACs)
/sd/handshakes/          *.pcapng captures + hcx-status.log
/sd/reports/             text reports
/usr/bin/bot-autostart   boot launcher (rc.local -> here)
/usr/bin/bot-report      builds + emails a recon/handshake report
/usr/bin/bot-mail        msmtp wrapper (if email enabled)
```

## Boot flow

`/etc/rc.local` → `bot-autostart` (30 s after boot): starts `pineapd`, enables
logging/capture, launches the chosen mode loop, and (if email) schedules a boot
report. An **every-N-hours** cron (default 2, chosen at setup) re-runs `bot-report`.

> **Runtime note:** `wl-refresh.py` and `recondump.py` use **Python 2.7** at
> `/sd/usr/bin/python` — the cloner's bundled interpreter (installed by
> `wpc-tools missing_packages`). This matches current cloner builds; a build that
> shipped Python 3 at that path would need those two helpers updated.

## Modes

- **switch** — reads the AR300M slide switch every 3 s (6 s debounce):
  - LEFT → `run_scan` recon loop (feeds the panel + recon.db), green LED.
  - RIGHT → one long-lived `hcxdumptool` with `--filterlist_ap=hcx-protect.list
    --filtermode=1` (deauth/PMKID **all except** your whitelist, capture
    handshakes, 2.4+5 GHz), red LED.
- **auto** — time-based alternation: N seconds recon, then M seconds passive
  capture, repeating. No deauth.
- **recon** — discovery only.
- **none** — nothing auto-runs.

## Why one long hcxdumptool instance (not a loop)

The AR300M's `rt2800usb` (RT5572) driver wedges if `hcxdumptool` is rapidly
start/stopped or the monitor vif is churned. The daemon therefore runs **one**
long-lived capture per mode entry and only tears it down on a **clean** mode
change (stop scan → pause hop → settle → hand off). To reload the whitelist,
flip the switch (LEFT→RIGHT) — never hot-restart hcxdumptool on the live monitor.

## Protected-network whitelist

`wl-refresh` reads `protect-ssids.conf` (SSID names; trailing `*` = prefix),
resolves every matching BSSID from **recon.db + the capture log + this router's
own APs**, and writes:

- `whitelist.lst` — `AA:BB:..` for the mdk3 Deauth module (whitelist mode).
- `hcx-protect.list` — `aabb..` lowercase for `hcxdumptool --filtermode=1`.

Because filters are **MAC-based**, an SSID can only be protected once at least
one of its BSSIDs has been observed. Prefix matching plus both data sources make
this robust (e.g. `Home*` auto-adds `Home-5G` the moment it's seen).

## Captive portal

The branded portal (`portal/index.php.template`, rebranded to your AP name and
accent) is served at the LAN root; its authorize button POSTs to
`/captiveportal/index.php`, the cloner's built-in mechanism that whitelists the
client for internet. Because clients have no internet before authorizing, the
page is **fully self-contained** (inline CSS/JS, no external assets).
