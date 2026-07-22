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
  - **Boot is always recon.** Deauth never auto-arms on boot — even if the switch
    is physically RIGHT the unit comes up in recon (green), and briefly flashes
    red/green as an "arm hint". To enter deauth, move the switch LEFT (recon) then
    back RIGHT. This makes a deauth-induced driver wedge → watchdog reboot land
    back in recon instead of looping. See *Boot safety & the RT5572 wedge* below.
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

The same fragile driver can wedge when a monitor vif is created or active
injection starts **while the radio is busy or the system hasn't settled** (cold
boot). A wedge stops feeding the hardware watchdog → the unit reboots in ~30 s.
If the switch were RIGHT and deauth auto-started every boot, that becomes a
**bootloop** — and repeated hard reboots can corrupt the ext4 journal on the USB
`/sd` (recover with `e2fsck -y /dev/sda1`). The switch daemon prevents this:

1. **Deauth never auto-arms on boot.** `FORCE_RECON=1` at start; the unit comes
   up in recon regardless of switch position. Deauth is enabled only after the
   switch is seen at LEFT and then moved to RIGHT (an explicit "arm"). A wedge →
   reboot therefore always returns to recon — a loop is impossible by design.
2. **Boot-settle grace** (`SETTLE=90`): nothing fragile runs until the system has
   been up ~90 s (skipped if already past it, e.g. a manual restart).
3. **Failsafe flag** `/sd/bot/.deauth_pending`: written before hcx starts, removed
   only after 75 s of stable capture. If it survives a reboot the wedge is logged.
4. **Passive capture by default**: deauth mode runs hcxdumptool as a passive
   dumper (`--disable_client_attacks --disable_ap_attacks`, no injection), which
   **cannot wedge the radio**. Active AP-deauth is opt-in (`touch
   /sd/bot/deauth-active`). `airmon-ng` bring-up is `timeout`-wrapped so it can
   never hang the daemon; if no monitor iface results, it falls back to recon.
5. **recon.db integrity guard** (in `bot-autostart`): a malformed sqlite `recon.db`
   (from an unclean shutdown) makes pineapd refuse to start — "Could not create
   aps table" — so **nothing** runs. The guard runs `pragma integrity_check` and
   quarantines a corrupt DB to `recon.db.malformed.*` so pineapd recreates a fresh
   one and boots normally. The whitelist file survives independently.

> **The worst case we actually hit:** repeated *active-deauth* wedges degraded the
> RT5572 into a state where it hung the driver **at boot probe** — before
> networking — so the unit bootlooped with no SSH window and re-corrupted `/sd`.
> A warm power-cycle did **not** clear it. The fix that did: **physically unplug
> the USB Wi-Fi card and re-plug it** (a cold USB re-enumeration resets the radio;
> a soft reboot does not). That is why deauth now defaults to passive — so the
> radio is never driven into that state in the first place. If you only want
> handshakes with zero risk, use **auto** (passive) or leave the switch LEFT
> (recon) — both are rock-stable; active deauth on this class of USB radio is the
> one fragile path.

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
