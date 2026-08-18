#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="MD Reader"
APP_BUNDLE="${APP_NAME}.app"

echo "→ Building Swift package ($CONFIG)…"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/MDReader"
if [[ ! -f "$BIN" ]]; then
    # arch-specific layout
    ARCH=$(uname -m)
    BIN=".build/${ARCH}-apple-macosx/$CONFIG/MDReader"
fi

if [[ ! -f "$BIN" ]]; then
    echo "Error: built binary not found"
    exit 1
fi

echo "→ Assembling ${APP_BUNDLE}…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/MDReader"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Localisations go straight into the bundle's Resources, not into an SPM
# resource bundle: SwiftUI and String(localized:) look them up in Bundle.main.
for lproj in Resources/*.lproj; do
    [[ -d "$lproj" ]] && cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
done

# Regenerate icon if missing, then copy into bundle.
if [[ ! -f AppIcon.icns ]]; then
    echo "→ Generating AppIcon.icns…"
    swift tools/make-icon.swift AppIcon.iconset >/dev/null
    iconutil -c icns AppIcon.iconset
fi
cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so Gatekeeper doesn't slam us locally.
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "✓ ${APP_BUNDLE} built"
