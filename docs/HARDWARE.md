# Hardware

## Recommended build (the "Shadowapple")

| Part | Notes |
|---|---|
| **GL.iNet GL-AR300M16-Ext** ("Shadow") | The target router. `mips_24kc` arch — **handshakes render in the panel** (the mipsel Mango does not). 16 MB NOR, external antennas. |
| **Dual-band USB Wi-Fi adapter** | Best chipset: **RT5572** (2.4 + 5 GHz). Becomes the monitor/capture radio. |
| **2.4 GHz USB Wi-Fi adapter** | **RT5370** recommended. Becomes the rogue-AP radio. |
| **USB flash drive** | Becomes `/sd` — holds packages, modules, captures, reports. |
| **USB hub, 3+ ports** | The AR300M has one USB port; the hub carries both adapters + the flash drive. |

> Other cloner-supported routers work too (200+ devices — see the
> [wifi-pineapple-cloner](https://github.com/xchwarze/wifi-pineapple-cloner)
> device list). The **hardware-switch** mode is specific to the AR300M's slide
> switch; other devices should use `auto` or `recon` mode.

## Supported USB chipsets (community-verified)

- **2.4 GHz:** RT5370 (confirmed), MT7601 *no*, plus MT760x / RT3070 / RT28xx family, RTL8187.
- **Dual-band:** RT5572 (confirmed), RT3572. **Avoid MT7612U** — many present as
  USB storage (`0e8d:2870`) instead of a Wi-Fi NIC.
- **Symptom of an unsupported adapter:** *"Monitor interface won't start! Try to run airmon-ng…"* — that's a catch-all; you need different hardware.

## Radio allocation (3 radios)

`setup.sh` auto-detects and assigns:

| Radio | Card | Role |
|---|---|---|
| onboard (ath9k) | built-in | **Uplink client** (internet) **+ management AP** — concurrent AP+STA repeater |
| dual-band USB | RT5572 | **PineAP monitor** — recon + handshake/PMKID capture, 2.4 **and** 5 GHz |
| 2.4 GHz USB | RT5370 | **PineAP source** — the open/rogue AP clients connect to |

Because all three radios are committed, **recon/capture and deauth cannot run at
the same instant** (they share the dual-band monitor). That is exactly why the
hardware switch (or the time-based `auto` mode) picks one at a time. The guest
AP, uplink, management AP, and captive portal keep running throughout.

## The hardware switch (AR300M)

The AR300M slide switch is exposed as two GPIOs (`button left`, `button right`).
On this unit only the **left** pin asserts reliably, so detection keys on it:

- **Full LEFT** → recon mode (green system LED)
- **anything else** → deauth + capture mode (red WLAN LED)

A ~6 s debounce prevents an accidental bump from starting deauth.
**On boot, if the switch is RIGHT it starts deauthing immediately** — keep it
LEFT unless you intend to attack.
