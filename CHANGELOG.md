# Changelog

All notable changes to Shadow-Apple-Installer are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); this project uses
[Semantic Versioning](https://semver.org/).

## [1.0.1] — 2026-07-22

Hardening release, driven by a real hardware bring-up. The headline finding: the
"RT5572 can't do active deauth" problem was **USB power starvation**, not the driver.
Everything here makes the unit boot-stable, self-healing, and — with adequate USB
power — able to run full active deauth indefinitely.

### Added
- **`docs/POWER-MOD.md`** — the USB-power root cause and three fixes (powered hub /
  VBUS jumper / drop one radio), with the on-board jumper mod detailed and a photo
  slot. This is the change that makes active deauth actually stable.
- **`/sd` auto-recovery** (in `bot-autostart`) — if the USB ext4 won't mount after a
  yanked-power / mid-write shutdown, the unit runs `e2fsck -y` and remounts on boot
  so automation self-heals instead of dying.
- **recon.db integrity guard** — a malformed sqlite `recon.db` used to make pineapd
  refuse to start ("Could not create aps table"); it's now `pragma integrity_check`ed
  and quarantined so pineapd recreates a fresh one and boots normally.
- **`deauth-active` flag** — `touch /sd/bot/deauth-active` switches deauth mode from
  the passive default to full active (client+AP) deauth.
- **Rapid-reboot bootloop guard** — 3+ fresh boots in quick succession hold recon
  until the switch is cycled LEFT→RIGHT; a normal reboot is unaffected.

### Changed
- **Boot follows the switch.** RIGHT boots straight into deauth, LEFT into recon
  (previously boot always came up in recon and required a LEFT→RIGHT "arm"). The
  bootloop guard above is the only override.
- **Deauth is passive by default** (`--disable_client_attacks --disable_ap_attacks`,
  no injection — cannot wedge the radio). Active deauth is opt-in via `deauth-active`.
- Monitor bring-up reuses pineapd's `wlan1mon`, is `timeout`-guarded, and **retries**
  instead of latching recon if the monitor isn't ready yet at boot.
- Whole tree normalized to LF (CRLF from a Windows editor was breaking device scripts).

### Fixed
- **RT5572 / rt2800usb bootloop and boot-probe hang.** Repeated active-deauth wedges
  (from power starvation) degraded the card until it hung the driver *at boot probe*,
  bootlooping with no SSH window and corrupting `/sd`. Fixed at the root by the power
  guidance above, plus the software guards (boot-follows-switch, passive default,
  bootloop guard, `/sd` + recon.db self-heal).
- 0-byte pcaps — were a symptom of the bootloop zeroing each fresh capture; captures
  now persist to `/sd/handshakes/capture_*.pcapng` and are verified growing.

## [1.0.0] — 2026-07-22

### Added
- Initial public release: interactive host-side `flash.sh` (checksum-verified cloner
  flash) and self-contained device-side `setup.sh` (hostname, password, uplink,
  custom rogue-AP name with matching Evil Portal rebrand, management AP, modules,
  captive portal, email reports, boot mode, protected-SSID whitelist).
- Device scripts (`lib/`), branded captive-portal template (`portal/`), and docs
  (`ARCHITECTURE.md`, `HARDWARE.md`, `LEGAL.md`). MIT licensed.

[1.0.1]: https://github.com/mr-tbot/Shadow-Apple-Installer/releases/tag/v1.0.1
[1.0.0]: https://github.com/mr-tbot/Shadow-Apple-Installer/releases/tag/v1.0.0
