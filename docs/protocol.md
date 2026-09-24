# XS Flow (Plus) configuration protocol

Reverse-engineered from Amkette's WebHID configurator
(`https://support.amkette.com/webapp/xs_flow_plus/`), mainly `index-DoJePk2b.js` and
`DeviceView-CZixg2Sr.js`. Those bundles are Amkette's code, so they aren't part of this
repo. To regenerate the test vectors, download them from that page into `docs/reference/`,
which is git-ignored.
The Swift encoders in `Sources/FlowCore/Hardware/Protocol.swift` are checked
byte-for-byte against the web app's own code in `Tests/FlowCoreTests/ProtocolTests.swift`.

## Transports

| Connection | VID:PID | Config channel |
|---|---|---|
| Bluetooth LE ("XS Flow S1") | 32C2:6621 | **None**. The descriptor has only report 1 (mouse) and 3 (consumer), with no feature reports |
| 2.4G dongle | 04F3:026F | Feature report 6 / 5, input report 4 |
| USB cable | 04F3:026E | same |

The web app filters on `vendorId: 1267` (0x04F3, Elan), so it never sees the Bluetooth device.

## Framing

* **Command:** `SetFeatureReport(6, body[31])`.
  * The builder makes `[cmd, seq, sub, payload…]` and pads it to 30 bytes, using 0xFF for most commands and 0x00 for polling rate and macro erase.
  * It then inserts `CHK = (6 + Σ bytes) & 0xFF` at index 3.
  * `seq` is a rolling counter (`seq = (seq + 1) % 256`, starting at 1, so the first command uses 2).
* **Ack:** wait about 60 ms, then `GetFeatureReport(6)`. `data[1] == 1` means success (data[0] is the report ID). The web app retries 3 times, waiting 100 + 50·n ms before each try.
* **Status poke:** `GetFeatureReport(5)`. The web app calls it on open and as a health check.
* **Status push:** input report 4 is `[link, dpiLevel, reportRate, battery%, batteryStatus, lightMode, ?, maxReportRate, sensorType]`.

## Commands

| cmd | sub | payload (before padding) |
|---|---|---|
| 0x01 buttons | 1 if ≤ 9 buttons; else 2, then 0x12 for slots 10–18 | 3 bytes per slot. In the first packet slots 4 and 5 are swapped (UI order is L, R, M, Fwd, Back; wire order is L, R, M, Back, Fwd). Unset = `FF FF FF` |
| 0x02 DPI | 2 = X, 0x12 = Y | `curLevel, enabledMask, 8 × (lo, hi)` with `value = dpi/100 − 1` (`/50` for sensors 0x95 and 0x50). Unused slots are `FF FF` |
| 0x03 DPI colours | 1 | 8 × `R G B` |
| 0x04 polling rate | 1 | `code`: 125=8, 250=4, 500=2, 1000=1, 2000=17, 4000=18, 8000=20 |
| 0x05 lift-off | 1 | 1 = 1 mm, 2 = 2 mm |
| 0x06 lighting | 1 | `FF, mode, (brightness<<4)\|speed, direction[, R, G, B]`. Modes: 0 off, 1 rainbow flow, 2 breathe, 3 steady, 4 neon, 5 marquee, 6 rainbow steady, 7 wave |
| 0x07 power | 1 | `sleepMinutes (1–15), moveWakeup, moveLighting` |
| 0x08 sensor | 1 | `angleSnap, motionSync, ripple` |
| 0x0F factory reset | 1 | `FF` |
| 0x11 macro erase | 1 | `FF`, padded with 0 |
| 0x10 macro data | `(chunk<<4)\|count` | `len, buttonIndex, data…`. Up to 25 bytes per chunk, padded to 31 bytes before the checksum |

## Button function codes

| bytes | meaning |
|---|---|
| `10 mask 00` | mouse button: 1 L, 2 R, 4 M, 8 Back, 0x10 Fwd, 0x20 wheel up, 0x40 wheel down |
| `70 mods key` | key combo. mods are HID modifier bits (1 Ctrl, 2 Shift, 4 Alt, 8 GUI/⌘); key is a HID usage |
| `80 lo hi` | consumer usage (0xCD play/pause, 0xB5 next, 0xB6 prev, 0xE9/0xEA volume, 0xE2 mute) |
| `40 01/02/03` | DPI cycle / + / − |
| `60 00` | disabled |
| `60 01` | mode switch |
| `60 04` | lighting toggle |
| `60 06/07` | tilt left / right |
| `60 08` | show desktop |
| `30 32 n` | fire key (n = repeats) |

XS Flow Plus factory layout (10 slots):
1. Left
2. Right
3. Middle
4. Forward
5. Back
6. Mode switch
7. DPI cycle
8. Tilt left
9. Tilt right
10. Show desktop
