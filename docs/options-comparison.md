# Click compared with Logi Options+

Scope: **MX Master 3 for Mac over Bluetooth**, with straightforward button bindings. Click is intended to cover that workflow without Logitech software running. It is not a complete Options+ replacement, and connection detection alone does not prove that physical inputs work correctly.

## Verification status

Click is in development. Software checks and device discovery have passed;
physical compatibility is still being evaluated. “Implemented” below describes
code and controls, not a hardware acceptance result.

## Features

“Implemented” describes the current code and visible controls; it is not a hardware test result.

| Feature | Logi Options+ | Click |
|---|---|---|
| Middle, back, forward, top and thumb button bindings | Supported | Implemented: keyboard shortcuts, navigation, editing, media and app launch |
| Application-specific bindings | Supported, with predefined profiles | Implemented for buttons; each profile has its own complete copy of the bindings |
| Thumb tap and four movement directions | Supported | Implemented when the device exposes the required HID++ capabilities |
| Gestures on other buttons | Supported | Thumb button only |
| Tracking speed, sensor DPI and SmartShift | Supported | Implemented where supported by the connected device |
| Wheel direction and scroll speed | Supported | Both directions; vertical speed in the UI |
| Thumbwheel mapped to tabs, zoom, volume or shortcuts | Supported | Horizontal scrolling and reversal only |
| Application-specific wheel settings | Supported | Point and scroll settings apply globally |
| Battery | Status and low-charge notifications | Status; no low-charge notification |
| Flow, Smart Actions, Actions Ring and plugins | Available subject to compatibility | Not implemented |
| Firmware updates | Supported device update path | Not implemented |
| Settings backup | Optional cloud backup | Local JSON file and export |

Logitech describes the mouse's controls in its [MX Master 3 for Mac guide](https://support.logi.com/hc/en-us/articles/360051303933-Getting-Started-MX-Master-3-for-Mac), extended thumbwheel actions in the [MX Master 3 guide](https://support.logi.com/hc/en-150/articles/360035271133-Getting-Started-MX-Master-3), and gestures on other buttons in its [Options+ button programming guide](https://hub.sync.logitech.com/options/post/programming-buttons-and-keys-in-options-ntwM6VsAEKhHACY). Its [current Options+ overview](https://www.logitech.com/en-us/software/logi-options-plus) covers automation, plugins and multi-computer features. MX Master 4 haptics are not a feature of the MX Master 3 hardware.

Two binding details affect migration:

- **Assign Back and Forward explicitly in Click.** The defaults pass raw mouse buttons 4 and 5 through. Click's navigation actions send ⌘[ and ⌘], so verify them in the applications you use.
- **Native middle-button behavior and an assigned “Middle click” differ.** Leaving the middle button at its default preserves holding and dragging. An assigned middle-click action sends one down/up pair; it does not hold the button for panning.

## Privacy and maintenance

Options+ does **not** require an account. Logitech says analytics and usage collection is consent-based, and users can opt out. Its privacy policy separately describes update and asset requests that record IP address, software version and connected devices. See the [current privacy policy](https://www.logitech.com/en-us/legal/privacy-policy) and [Options+ security whitepaper](https://secure.logitech.com/assets/66289/logi-options-security-whitepaper.pdf).

Click has no account, cloud configuration, analytics, automatic updater or application network client. Its source privacy check is a regression scan, not a network sandbox. Settings remain in a local JSON file. The tradeoff is local maintenance: Click uses some private macOS input APIs, and new macOS releases need verification.

## Trial before uninstalling

Keep the existing installation and settings while testing. Closing the Options+
window does not establish that its background agent has stopped. Before an
independent test, identify the active remapper process and its launch item,
record a matching recovery operation, and stop only that verified service.
Names and paths vary by installation; do not copy an unverified launchctl target.
Keep its launch configuration and verify the process stays stopped. A new login
may load it again. This reversible trial is separate from uninstalling.

With both utilities quit, power-cycle the mouse once to clear any leftover button diversion. Then start Click alone and run these checks:

1. **Basic input:** left/right clicks, dragging, native middle-click and held middle-button behavior remain usable. Both wheels scroll in the intended direction.
2. **Bindings:** assign Back/Forward and the desired top/thumb actions. Repeat each press and release in the actual destination apps; expect exactly one action per press, with no stuck or doubled input.
3. **Shortcuts and gestures:** test a recorded shortcut. If gestures are used, test all four directions and a stationary thumb tap.
4. **Application profiles:** give one app a different binding, switch between it and another app, and confirm the correct action follows focus. Wheel settings remain global.
5. **Recovery:** test sleep/wake and mouse off/on over Bluetooth. Confirm settings and bindings return; investigate any need for manual Refresh before treating recovery as verified.
6. **Persistence and exit:** quit Click and check native operation returns. Reopen it and confirm saved bindings. If launch at login is needed, test a logout/login with it enabled.

Only uninstall when these checks pass and the missing features are acceptable. Successful compilation, tests, screenshots and HID++ discovery cannot replace these physical checks.

## Removing Options+

Use Logitech's [official complete-uninstall instructions](https://support.logi.com/hc/en-us/articles/26832619554711-How-to-completely-uninstall-Logi-Options-and-Options). They describe support-file and launch-item cleanup followed by a restart. Logitech also documents an uninstall flag in its [installer feature guide](https://hub.sync.logitech.com/options/post/options-silent-installation-feature-flags-RnX8O7v5xTQ41mq); verify the current vendor executable and its supported arguments before using it.

Do not assume the legacy Options uninstaller exists for Options+, or remove every Logitech folder indiscriminately when other Logitech products are installed. Preserve any settings needed for rollback before removal. After uninstalling and restarting, confirm the Options+ processes remain absent and repeat the essential binding checks with Click.
