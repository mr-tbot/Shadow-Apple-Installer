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
  - RIGHT → one long-lived `hcxdumptool` capture (all except your whitelist,
    2.4+5 GHz), red LED. **Passive by default** (`--disable_client_attacks
    --disable_ap_attacks` = a passive dumper: grabs handshakes/PMKID that occur,
    no injection) so it can never wedge the radio. Opt into **active** AP-deauth
    (`--disable_client_attacks` only — stronger, but may wedge a fragile card) with
    `touch /sd/bot/deauth-active`.
  - **Boot follows the switch** (RIGHT = deauth after the ~90 s settle grace). The
    only exception: if a previous deauth **wedged** the radio, the unit holds recon
    until you cycle the switch LEFT→RIGHT — so a wedge self-heals instead of
    bootlooping. See *Boot safety & the RT5572 wedge* below, and note active deauth
    needs adequate USB power.
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

## Boot safety & the RT5572 wedge

### The real root cause: USB power

The single biggest source of "the radio wedges under deauth" on this class of unit
is **USB power starvation**, not the driver. Two USB Wi-Fi cards (≈450 mA each) plus
a USB flash drive (≈200 mA) pull ~1.1 A through the AR300M's USB-A port, which is
current-limited to ~500 mA. The instant a radio **transmits** (deauth is the worst
case) the VBUS sags, the card browns out and **resets** (`usb ... reset ... device`
in dmesg), `rt2800usb` wedges, the watchdog fires, and it reboots — and repeated
hard reboots corrupt the ext4 journal on `/sd` (recover: `e2fsck -y /dev/sda1`).

**Give the radios real current and active deauth becomes stable.** Any of:
- a **powered USB hub** (its own adapter), or
- **bypass the port's current limiter** — jumper 5 V from the input rail to the
  USB-A/hub VBUS, fed by a 5 V/2–3 A supply (you lose over-current protection), or
- **run one USB radio** instead of two (halves the load, kills the dual-radio TX
  contention) — see the two-radio note below.

With adequate power, full active deauth (client+AP) runs indefinitely with **zero**
USB resets. On a power-starved unit, use the passive default (below) instead.

### The daemon's software guards (belt-and-suspenders)

1. **Boot follows the switch; a wedge can't loop.** The unit boots into whatever the
   switch selects (RIGHT = deauth after the settle grace). But a deauth that wedges
   leaves `/sd/bot/.deauth_pending`; if that flag survives a reboot the daemon
   **forces recon until the switch is cycled LEFT→RIGHT** — so a wedge self-heals to
   recon instead of bootlooping.
2. **Boot-settle grace** (`SETTLE=90`): nothing fragile runs until the system has
   been up ~90 s (skipped if already past it, e.g. a manual restart).
3. **Passive capture by default**: unless `/sd/bot/deauth-active` exists, deauth mode
   runs hcxdumptool as a passive dumper (`--disable_client_attacks
   --disable_ap_attacks`, no injection) which **cannot wedge the radio**. `touch
   /sd/bot/deauth-active` to enable full active deauth (only do this once the radios
   have adequate power). `airmon-ng` bring-up is `timeout`-wrapped; if no monitor
   iface results it falls back to recon.
4. **recon.db integrity guard** (in `bot-autostart`): a malformed sqlite `recon.db`
   (from an unclean shutdown) makes pineapd refuse to start — "Could not create aps
   table" — so **nothing** runs. The guard runs `pragma integrity_check` and
   quarantines a corrupt DB to `recon.db.malformed.*` so pineapd recreates a fresh
   one and boots normally. The whitelist file survives independently.

> **If a radio ever wedges hard** (bootloops with no SSH window), a warm power-cycle
> may not clear it — **physically re-seat the USB card** (cold re-enumeration resets
> the radio; a soft reboot does not). Then fix the underlying power. If you only want
> handshakes with zero risk, use the passive default or leave the switch LEFT (recon)
> — both are rock-stable regardless of power.

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
