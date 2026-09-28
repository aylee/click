# Click

Click is a local macOS menu bar app for configuring Logitech MX Master mice. It uses SwiftUI and AppKit, talks to the mouse over HID++, and processes mouse events with Core Graphics. It is an MIT-licensed fork of [LoLiMouse](https://github.com/fedorananin/lolimouse).

**Development status:** the current source is **0.1.0, build 7**. Hardware
acceptance is incomplete; device support has not yet been verified.

## What it does

- Assign navigation, editing, media, app-launch actions or keyboard shortcuts to mouse buttons.
- Set separate button bindings for individual applications.
- Configure thumb tap and directional gestures on capable devices.
- Adjust supported tracking, DPI, wheel mode, scrolling direction and speed.
- Store settings locally, with an optional menu bar icon and launch at login.

The initial hardware target is **MX Master 3 for Mac over Bluetooth**. Controls
appear according to device capabilities; other MX Master models and receivers
need their own testing. Flow, firmware updates and Logitech automation services
are outside the current scope.

## Build

Requires macOS 15 or later and Swift 6 Command Line Tools. The package currently compiles in Swift 5 language mode. There are no external package dependencies.

```sh
Scripts/check.sh
Scripts/package_app.sh
```

The packager creates `build/Click.app` and `build/Click-macOS.zip` for the Mac's current architecture. The app uses the case-sensitive bundle identifier `ai.alexlee.Click`. It is ad-hoc signed for local use, not notarized for distribution. Version values live in `Scripts/version.conf`.

Quit a running copy before rebuilding. To build and open a debug copy:

```sh
Scripts/build_and_run.sh
```

## Use

Quit Logi Options+ and other mouse remappers before enabling Click's controls. Open the app, grant the requested Accessibility and Input Monitoring permissions in System Settings, and reopen Click if needed. Rebuilding an ad-hoc signed app may require granting permissions again. If System Settings shows Click enabled but Click still reports missing access after a restart, remove only Click from each permission list, add the installed app again, and reopen it.

Select a button on the mouse diagram to assign a shortcut, navigation, editing, media, or app-launch action. Add an application to give it a separate set of button bindings. Click also exposes supported pointer/DPI, wheel/SmartShift, scrolling, and thumb gesture controls. Keep each setting disabled until you want Click to manage it. Configuration is stored locally at `~/Library/Application Support/Click/config.json`. Launch at login is optional. **Click → Pause customizations** temporarily stops applying your bindings and restores previous device settings; **Resume customizations** reapplies them. macOS Accessibility and Input Monitoring grants stay unchanged. This command is also available from the optional menu bar icon.

There is no account, cloud configuration, analytics, automatic updater, or application network client. The privacy check is a source regression scan; it is not a network sandbox. The app uses some private macOS input symbols, which can change with macOS updates.

See the [Options+ comparison and migration checks](docs/options-comparison.md) for feature coverage and the independent hardware trial.

## Checks and diagnostics

```sh
Scripts/check.sh build       # Compile the app without launching it
Scripts/check.sh test        # Run the dependency-free ClickTests executable
Scripts/check.sh privacy     # Scan source and package declarations
swift run Click --diagnose   # Read-only inventory; no HID open/seize or settings writes
swift run Click --preview    # Isolated temporary settings; hardware remains off
```

The executable test harness checks software behavior without replacing hands-on mouse testing. Reconnect, sleep/wake, button release, SmartShift and scrolling need validation on the actual device and transport. There is no claim of Logitech Flow, firmware update, or MX Master 4 haptic parity.

For a Bolt/Unifying mouse power cycle while the receiver stays connected, use **Settings → Refresh** to reapply settings. Quitting or disabling Click attempts to restore the original hardware state, recovering diverted buttons before wheel/DPI settings. An asleep, disconnected, or permission-denied mouse may be unreachable; if a thumb/top button remains inactive after a crash or failed cleanup, power-cycle the mouse.

The Dock icon uses committed artwork in `Resources/AppIcon.png`; regenerate its macOS sizes locally with `swift Scripts/build_icon.swift`. The creation prompt is in `Resources/AppIcon-prompt.txt`. The in-app mouse illustration is also original generated artwork. See
[attribution](THIRD_PARTY_NOTICES.md), [architecture](docs/architecture.md), and
[contributing](CONTRIBUTING.md) for implementation and contribution details.

## License

[MIT](LICENSE), retaining LoLiMouse attribution. Click is an independent project
and is not affiliated with Logitech.
