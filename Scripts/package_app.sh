#!/bin/bash
# Assemble and ad-hoc sign a local macOS app from SwiftPM output.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
CONF=${1:-release}
case "$CONF" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;; esac
source "$ROOT/Scripts/version.conf"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
    echo "Invalid version.conf" >&2; exit 1;
}
swift build -c "$CONF" --product Click
BIN=$(swift build -c "$CONF" --show-bin-path)
APP="$ROOT/build/Click.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Click" "$APP/Contents/MacOS/Click"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
ditto "$BIN/Click_ClickApp.bundle" "$APP/Contents/Resources/Click_ClickApp.bundle"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/Click-macOS.zip"
echo "Created $APP ($VERSION build $BUILD_NUMBER; local ad-hoc signature)"
