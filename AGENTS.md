# Click

A local, native macOS MX Master utility. SwiftUI/AppKit UI, IOKit HID access, HID++ configuration, and Core Graphics input processing. The source is derived from LoLiMouse; retain the original MIT license and attribution.

- Use existing targets and native frameworks. No external dependencies, account, network client, telemetry, updater, or cloud service.
- Preserve the case-sensitive bundle identifier `ai.alexlee.Click`. Version values live in `Scripts/version.conf`.
- Keep user-facing controls capability-driven. Do not claim device/transport support from compilation alone.
- Keep the mouse usable when permissions are missing, settings are disabled, or a request fails. HID writes, diversion cleanup, and input-event paths need focused verification.
- Private input APIs live in `Sources/IOKitSPI`; keep additions narrow and document the macOS compatibility cost.
- Do not overwrite unrelated edits. Keep personal session logs and local configuration outside this repository; public compatibility claims need reproducible evidence.

Checks: `Scripts/check.sh` (or `build`, `test`, `privacy` lanes). `Scripts/package_app.sh` makes a local ad-hoc signed bundle; it does not launch or install it. `Scripts/build_and_run.sh` launches explicitly. Tests run with `swift run ClickTests`; this package does not use XCTest.

Do not commit, create remotes, publish, install, or change the user's mouse configuration without task authorization. Packaging does not require a keychain identity. Report failed, skipped, hardware-unverified, and passing checks separately.

Commits use `type(scope): short lowercase summary`; use scopes such as `app`, `hid`, `input`, `docs`, or `ci`. Never bypass hooks.
