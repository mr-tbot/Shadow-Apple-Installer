# Powering the USB Radios — the fix that makes active deauth stable

Active deauth on the AR300M's USB Wi-Fi cards is gated by one thing more than any
other: **how much current the USB-A port can actually deliver.** Get that right and
full active deauth runs indefinitely. Get it wrong and the radio browns out
mid-transmit, the driver wedges, and the unit reboots. This page explains the
problem and three ways to fix it — including the on-board jumper mod used on the
reference unit.

---

## The problem: USB power starvation

The AR300M16 exposes a single USB-A host port, and that port's VBUS is
current-limited to roughly **500 mA** (the USB 2.0 default, enforced by a load-switch
or polyfuse on the 5 V rail). A typical Shadow-Apple build hangs three devices off it
through a hub:

| Device | Max draw (USB descriptor) |
| --- | --- |
| RT5572 dual-band Wi-Fi (monitor / capture / deauth) | ~450 mA |
| RT5370 2.4 GHz Wi-Fi (PineAP source AP) | ~450 mA |
| USB flash drive (`/sd`) | ~200 mA |
| **Total** | **~1.1 A** |

That is roughly **double** what the port is meant to supply. At idle it is merely
marginal; the instant a radio transmits — and **deauth is the heaviest TX load there
is** — current spikes, VBUS sags, and the card **browns out and resets.** In `dmesg`
that appears as:

```text
usb 1-1.2: reset high-speed USB device number 4 using ehci-platform
```

When the card resets, the `rt2800usb` driver wedges, stops feeding the 30-second
hardware watchdog, and the unit reboots. Repeated hard reboots can even corrupt the
ext4 journal on `/sd`. Every "the RT5572 can't do deauth" symptom traces back here.
**The card was never the problem — it was starved.**

> **Not every reset is the tell.** One or two `reset ... device number` lines appear
> at **~12 s on every boot** as part of normal USB enumeration. The power symptom is
> resets that happen **under load** — i.e. new reset lines appearing *while a radio is
> transmitting*.

---

## Three fixes

Pick whichever suits your hardware. All three make active deauth stable.

### 1. Powered USB hub — no soldering

Use a USB hub with its **own power adapter**. The radios draw from the hub's supply
instead of the router's port. Keeps over-current protection. Easiest and safest.

### 2. Run one USB radio — no power work

Drop the RT5370. That halves the USB load and removes the dual-radio TX contention
outright. You lose the PineAP source AP (your open guest SSID); recon, capture and
deauth all stay on the RT5572. See the radio map in [ARCHITECTURE.md](ARCHITECTURE.md).

### 3. VBUS jumper mod — on-board (the reference unit)

Bypass the port's current limiter and feed the USB-A / hub VBUS straight from the
input rail, backed by a supply that can actually deliver the current. This is what is
on the reference unit and what makes **both** radios plus full active deauth stable.

---

## The VBUS jumper mod, in detail

**Principle.** The wall supply can source well over 1 A; the bottleneck is the
limiting element (load-switch or polyfuse) *between* the 5 V input and the USB-A
VBUS. Bridge across it so the port draws directly from the input rail.

**What you bridge:**

- **+5 V from the input rail** (the power-input side, *upstream* of the limiter)
  **→ +5 V on the USB-A / hub VBUS** (*downstream* of the limiter).
- **Ground is already common** across the board — do **not** run a second ground
  wire.

**What you must supply:**

- A **5 V / 2–3 A** adapter. After the mod you are sourcing board (~400 mA) + two
  radios (~900 mA peak) + flash (~200 mA) ≈ **1.5 A** straight off the input. A
  5 V / 1 A brick will still sag — the jumper only helps if the supply behind it can
  deliver the current.
- **Wire:** 26 AWG or heavier carries 1.5 A over that short run with margin. Keep the
  solder joints clean and mechanically secure.

**Reference photo** — the jumper in place on the AR300M board:

![VBUS jumper mod on the AR300M board](images/power-mod-jumper.jpg)

*Photo goes here. Save it as `docs/images/power-mod-jumper.jpg`.*

### Safety — read before you cut

- **You lose over-current protection on that port.** A shorted dongle now dumps
  straight into your adapter and board with no fuse in the path. Only do this if you
  are comfortable with that trade-off.
- **VBUS becomes always-on** — the SoC can no longer power-cycle the USB port in
  software. Minor; only matters if you relied on a software USB reset.
- This is an **irreversible hardware modification to your own device.** Do it at your
  own risk. Authorized testing only.

---

## Verify it worked

After the mod (or hub, or single-radio path), confirm the radios stop browning out
under transmit load.

1. Enable active deauth:

   ```text
   touch /sd/bot/deauth-active
   ```

2. Set the hardware switch to **RIGHT** (deauth) and let it run ~90 seconds.

3. Confirm no resets happen **under load**:

   ```text
   dmesg | grep -c 'reset .*device number'
   ```

   The count should **not climb** while deauth is transmitting (the one or two
   entries from boot enumeration are expected). Meanwhile `uptime` should keep
   climbing, the capture `.pcapng` in `/sd/handshakes/` should grow, and
   `/sd/handshakes/hcx-status.log` should show `EAPOL` / `MP:M...` handshake lines.

**Reference unit result:** 90 s of full active deauth (client + AP) → **zero** new
USB resets, uptime climbing, handshake captured (`MP:M2M3 ... EAPOLTIME`). That is
the target — if you see it, active deauth is stable on your unit.
