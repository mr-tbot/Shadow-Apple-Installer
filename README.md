# 🍎🖤 Shadow-Apple-Installer

**Turn a ~$35 GL.iNet AR300M ("Shadow") into a self-reporting Wi-Fi security
appliance — with one interactive installer.**

Shadow-Apple-Installer flashes xchwarze's [WiFi Pineapple
Cloner](https://github.com/xchwarze/wifi-pineapple-cloner) onto an AR300M-class
router and then **interactively** configures the whole rig: internet uplink +
management AP (repeater), a branded captive portal, a loaded module set,
email reports, protected-network whitelisting, and a **hardware-switch-driven
recon ↔ deauth+capture** workflow. It asks what you want, applies only that, and
**hard-codes none of your personal data.**

> ⚠️ **Authorized use only.** This automates rogue APs, deauthentication, and
> handshake/PMKID capture. Running it against networks or devices you don't own
> or aren't authorized to test is illegal in most places. **Read
> [docs/LEGAL.md](docs/LEGAL.md) first.**

---

## ✨ Features

- **Two-command install** — `flash.sh` on your PC, `setup.sh` on the device.
- **Interactive & modular** — toggle each feature on/off; nothing is forced.
- **Custom AP name** — name the open/rogue SSID whatever you like; the captive
  portal **auto-rebrands to match** (name + accent colour).
- **Intelligent radio allocation** — onboard = uplink + management AP (repeater),
  dual-band USB = monitor/capture (2.4 **and** 5 GHz), 2.4 USB = rogue AP.
- **Hardware-switch modes** (AR300M): **Left = recon** (green LED),
  **Right = deauth + handshake capture** (red LED), 6 s debounce. Boot is always
  recon and deauth **never auto-arms** — a driver wedge can never bootloop; arm
  deauth by moving the switch Left→Right.
- **Whitelist your own networks** — protect SSIDs by name (prefix `Home*`
  supported); BSSIDs auto-resolve from scans + captures. In deauth mode the
  device hits everything **except** your list.
- **Passive/active handshake + PMKID capture** to `.pcapng` (hashcat `-m 22000`).
- **Branded captive portal** — animated orange/black, mouse/touch-reactive,
  accept-terms → get internet (fully self-contained; no external assets).
- **Curated ~30-module set** (or pick your own) + all binary deps on `/sd`.
- **Email reports** every N hours (recon + handshake/PMKID summary) — optional.
- **Boot-persistent** and hardened against the AR300M's finicky USB-Wi-Fi driver.

## 🧰 Hardware

GL.iNet **GL-AR300M16-Ext** + a **dual-band (RT5572)** USB adapter + a
**2.4 GHz (RT5370)** USB adapter + a USB flash drive on a **3-port hub**.
Full details and supported chipsets: **[docs/HARDWARE.md](docs/HARDWARE.md)**.

## 🚀 Quickstart

**1. Flash** (on your computer — Git Bash / Linux / macOS; router on LAN):

```sh
sh flash.sh
```
It asks for the router IP + password + model, downloads and **checksum-verifies**
the cloner image, and flashes it. The device reboots to `http://172.16.42.1:1471/`.

**2. Configure** (on the freshly-flashed device):

```sh
# copy setup.sh to the device (dropbear has no SFTP, so stream it):
cat setup.sh | ssh root@172.16.42.1 "cat > /tmp/setup.sh"
# run it with a TTY so the prompts work:
ssh -t root@172.16.42.1 "sh /tmp/setup.sh"
```
…or paste `setup.sh` into the panel's **Terminal** module.

`setup.sh` walks you through: hostname/password · uplink Wi-Fi · **open/rogue AP
name** · management AP · modules · **captive portal** · email reports ·
**boot mode** · protected SSIDs — then applies your choices.

## 🎛️ Modes

| Mode | What it does |
|---|---|
| **switch** | AR300M slide switch: **Left** = recon only, **Right** = deauth + capture (whitelist-shielded). LED shows mode. |
| **auto** | Time-based: alternate recon and passive capture automatically (no deauth). |
| **recon** | Discovery only — feeds the panel + reports. |
| **none** | Nothing auto-runs at boot. |

## 📡 Using it

- **Panel:** `http://172.16.42.1:1471/` (or join your management AP).
- **Handshakes:** `/sd/handshakes/*.pcapng`. Crack them:
  ```sh
  hcxpcapngtool /sd/handshakes/*.pcapng -o hs.22000
  hashcat -m 22000 hs.22000 <wordlist>
  ```
- **Reports:** emailed every N hours (if enabled) and saved to `/sd/reports/`.

## 📁 Repo layout

```
flash.sh                 host-side flasher
setup.sh                 device-side interactive installer (self-contained)
lib/                     device scripts (readable source; embedded into setup.sh)
portal/index.php.template branded captive portal (with {{placeholders}})
config/                  protect-ssids.conf.example
scripts/build.sh         regenerate setup.sh from lib/ + portal/
docs/                    ARCHITECTURE.md · HARDWARE.md · LEGAL.md
```

Architecture details: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

## 🙏 Credits

- **[xchwarze](https://github.com/xchwarze/wifi-pineapple-cloner)** — the WiFi
  Pineapple Cloner firmware this builds on. This project just installs and
  configures it; all the hard porting work is theirs.
- **SHUR1K-N** — the "Wi-Fi Shadowapple" build/videos and
  [resources](https://github.com/SHUR1K-N/WiFi-Shadowapple-Resources) that
  inspired the hardware recipe.
- **Hak5** — the original Wi-Fi Pineapple. Support them and buy the real hardware.

## 📜 License

MIT — see [LICENSE](LICENSE). Offensive tooling; **authorized use only**
([docs/LEGAL.md](docs/LEGAL.md)).
