# Contributing to Click

Keep changes focused on local mouse configuration. Preserve the original MIT
attribution and discuss new dependencies or network features before adding them.

## Build and check

Use macOS 15 or later with Swift 6 Command Line Tools. From the repository root:

```sh
Scripts/check.sh
Scripts/package_app.sh release
unzip -tq build/Click-macOS.zip
```

The checks compile the app, run the `ClickTests` executable, and scan for selected
privacy regressions. Packaging validates the bundle plist and ad-hoc signature.
These commands do not launch or install Click. For an isolated UI preview, run
`swift run Click --preview`; it does not open mouse hardware.

CI runs these checks on `macos-15` with Xcode 16.4. GitHub documents the
[runner image and installed Xcode versions](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md),
and Apple lists its [Swift compiler and SDK support](https://developer.apple.com/xcode/system-requirements).
CI neither publishes an app nor verifies physical mouse behavior.

## Submit useful evidence

Explain the problem, resulting behavior, and checks run. Keep failed, skipped,
and hardware-unverified results explicit. Add focused regression coverage when
changing input routing, HID++ operations, persistence, or restoration.

For hardware changes, report the mouse model, connection type, macOS version,
and physical results for the affected controls. Check press/release pairing,
pause/resume, quit/reopen, reconnect, and permission loss when relevant. Verify
other remappers are stopped during the trial. The [Options+ comparison](docs/options-comparison.md)
provides broader migration checks. Detection, an Applied status, or synthetic
events alone do not establish that a physical binding works.

Share only the smallest relevant, redacted diagnostic excerpt. Do not include
keystrokes, credentials, full configuration exports, device serial numbers,
private application names, or unrelated system logs. State whether a result was
observed on hardware or inferred from source/tests.
