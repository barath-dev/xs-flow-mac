# MouseDriver

A macOS menu-bar configurator for the **Amkette XS Flow (Plus)** mouse.

There are two layers:

1. **Software remapping. Works over Bluetooth.** Rebind any button to:
   * a keyboard shortcut
   * Mission Control, Spaces or other system actions
   * a media key
   * another mouse button
   * opening an app or URL, or running a shell command
   * a hold-to-scroll-horizontally or hold-to-zoom modifier

   You can also reverse or speed up the wheel for this mouse only (your trackpad keeps its setting), set a per-mouse tracking speed, and create per-app profiles.
   In the config, buttons use HID numbering: 1 left, 2 right, 3 middle, 4 back, 5 forward. Wheel tilt and the DPI button can't be remapped because the mouse never reports them to the Mac.
2. **Onboard settings (experimental). Needs the 2.4G dongle or USB cable.** DPI levels, polling rate, lighting, sleep timer and the onboard button map. These are written to the mouse's own memory using the protocol in [docs/protocol.md](docs/protocol.md). The protocol matches the vendor web app's code, but it hasn't been tried on a real dongle yet, so it's off by default. To turn it on, run `defaults write com.barathwaj.mousedriver experimentalHardware -bool true` and relaunch the app to get the Hardware tab. For the CLI, add `--experimental` to `flowctl hw` commands.

## Build & run

```sh
./scripts/bundle.sh          # → build/MouseDriver.app and build/flowctl
open build/MouseDriver.app
```

On first launch, grant **Input Monitoring** and **Accessibility** when the Settings window asks (System Settings → Privacy & Security). Remapping starts on its own once both are on. The app also asks for **Bluetooth** access, which it uses to read the battery level.

Ad-hoc signed builds lose those permissions every time you rebuild. To avoid that, run `./scripts/create-signing-cert.sh` once. It creates a local signing certificate that `bundle.sh` then uses.

## flowctl (CLI)

```
flowctl list                     connected interfaces (and whether a config channel exists)
flowctl monitor                  raw button/wheel events from the mouse
flowctl battery                  battery over Bluetooth LE
flowctl run [--config file]      headless remapping engine
flowctl example-config           sample config JSON
flowctl hw status|rate|dpi|light|button|sleep|reset --experimental   onboard settings (dongle/cable)
```

Config lives in `~/Library/Application Support/MouseDriver/config.json`. The app writes it, but you can also edit it by hand; missing fields fall back to defaults.

## Layout

* `Sources/FlowCore`: the library.
  * `Devices`: IOHIDManager discovery and BLE battery.
  * `Engine`: event tap, device correlation, actions, scroll and pointer.
  * `Config`: config model and JSON store.
  * `Hardware`: packets and the dongle transport.
* `Sources/MouseDriverApp`: the SwiftUI menu-bar app.
* `Sources/flowctl`: the CLI.
* `Tests/FlowCoreTests`: run with `swift test`. Includes golden vectors generated from the vendor web app's own code.

## License

GPL-3.0. See [LICENSE](LICENSE).

Not affiliated with Amkette.
