# Legal & Responsible Use

**Read this before you use Shadow-Apple-Installer.**

This project automates offensive Wi-Fi capabilities:

- **Rogue / open access points** designed to attract client devices.
- **Deauthentication / disassociation** of nearby stations.
- **Handshake and PMKID capture** for offline password cracking.
- **Captive-portal ("Evil Portal") credential/consent flows.**

## The rule

**Only operate this against networks and devices that you own, or that you have
explicit, written authorization to test.**

Deauthenticating, capturing handshakes from, or luring clients of networks you
do not control is illegal in most jurisdictions — including under the U.S.
Computer Fraud and Abuse Act, the U.K. Computer Misuse Act, and equivalent laws
worldwide. Transmitting deauthentication frames can also violate radio
regulations (e.g. FCC Part 15) regardless of intent.

The **protected-SSID whitelist** exists so you can shield your own networks, but
it does **not** make attacking third-party networks lawful. In deauth mode the
device attacks **every** in-range access point except the ones you whitelist —
so only enable it in an **RF-isolated lab** or an environment you are authorized
to test.

## Your responsibility

- You are solely responsible for how you use this software.
- Get authorization in writing. Keep it.
- Prefer a shielded/faraday environment or your own isolated lab.
- Follow responsible-disclosure practices for anything you find.

The authors and contributors provide this for **education, research, and
authorized security testing only**, and accept **no liability** for misuse.
If you are not certain your use is legal and authorized, **do not run it.**
