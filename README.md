# MouseDriver

A macOS menu-bar app for customising your mouse's buttons, scrolling and speed, without touching your trackpad. It has extra support for the **Amkette XS Flow (Plus)**.

It works with any external mouse, whether Bluetooth, USB or a wireless receiver. So far it has been tested with the XS Flow Plus over Bluetooth. Reports from other mice are very welcome.

## What it does

**Button remapping, for any mouse.** You can rebind any button to:
* a keyboard shortcut
* Mission Control, Spaces or other system actions
* a media key
* another mouse button
* opening an app or URL, or running a shell command
* a hold-to-scroll-horizontally or hold-to-zoom modifier

You can also:
* reverse or speed up the wheel for your mice only (your trackpad keeps its setting)
* set a separate tracking speed for your mice
* create per-app profiles
* see battery levels for Bluetooth mice that report them

Each event is matched to the mouse that sent it. The **Mice** tab lists every connected mouse, and you can switch off any mouse you want left exactly as macOS has it.

In the config, buttons use HID numbering: 1 left, 2 right, 3 middle, 4 back, 5 forward. Buttons a mouse handles internally, such as a DPI button, never reach the Mac and can't be remapped. On the XS Flow that includes wheel tilt.

**Amkette XS Flow onboard settings (experimental). Needs the 2.4G dongle or USB cable.** DPI levels, polling rate, lighting, sleep timer and the onboard button map. These are written to the mouse's own memory using the protocol in [docs/protocol.md](docs/protocol.md). The protocol matches the vendor web app's code, but it hasn't been tried on a real dongle yet, so it's off by default. To turn it on, run `defaults write com.barathwaj.mousedriver experimentalHardware -bool true` and relaunch the app to get the Hardware tab. For the CLI, add `--experimental` to `flowctl hw` commands.

## Install

Download the latest zip from [Releases](https://github.com/barath-dev/xs-flow-mac/releases), unzip it, and move **MouseDriver.app** to Applications. It needs macOS 14 or later and runs on Apple silicon and Intel.

The beta isn't notarized, so the first time you open it macOS will block it. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

When the app asks, grant **Accessibility**. That's the only permission remapping needs: it lets MouseDriver change what a mouse click or scroll does. It only watches mouse events and never reads your keyboard. The app also asks for **Bluetooth**, which it only uses to read battery levels.

## Build & run

```sh
./scripts/bundle.sh          # → build/MouseDriver.app and build/flowctl
open build/MouseDriver.app
```

Ad-hoc signed builds lose their permissions every time you rebuild. To avoid that, run `./scripts/create-signing-cert.sh` once. It creates a local signing certificate that `bundle.sh` then uses. `./scripts/release.sh` builds the universal release zips.

## flowctl (CLI)

```
flowctl list                     connected mice and their HID interfaces
flowctl monitor                  raw button/wheel events from external mice (terminal needs Input Monitoring)
flowctl battery                  battery of Bluetooth LE mice
flowctl pointer                  each mouse's current tracking speed
flowctl run [--config file]      headless remapping engine (terminal needs Accessibility)
flowctl example-config           sample config JSON
flowctl hw status|rate|dpi|light|button|sleep|reset --experimental   XS Flow onboard settings (dongle/cable)
```

Config lives in `~/Library/Application Support/MouseDriver/config.json`. The app writes it, but you can also edit it by hand; missing fields fall back to defaults.

## Layout

* `Sources/FlowCore`: the library.
  * `Devices`: mouse discovery (HID event system and IOHIDManager), per-event device lookup, BLE battery.
  * `Engine`: event tap, actions, scroll and pointer.
  * `Config`: config model and JSON store.
  * `Hardware`: XS Flow packets and the dongle transport.
* `Sources/MouseDriverApp`: the SwiftUI menu-bar app.
* `Sources/flowctl`: the CLI.
* `Tests/FlowCoreTests`: run with `swift test`. Includes golden vectors generated from the vendor web app's own code.

## License

GPL-3.0. See [LICENSE](LICENSE).

Not affiliated with Amkette.
