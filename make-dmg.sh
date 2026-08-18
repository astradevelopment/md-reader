#!/bin/bash
# Builds MD Reader and packages it as a drag-to-Applications disk image.
#
# The Finder layout (window size, icon positions, backdrop) is applied by
# AppleScript against a mounted read-write image, then frozen by converting it
# to a compressed read-only one. macOS will ask once for permission to control
# Finder; without it the image still builds, just with the default plain layout.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MD Reader"
APP="${APP_NAME}.app"
VOL="${APP_NAME}"
DMG="${APP_NAME}.dmg"
STAGE="build/stage"
RW_DMG="build/rw.dmg"

echo "→ Building the app…"
./build.sh release >/dev/null

echo "→ Rendering the installer backdrop…"
mkdir -p build/dmg
swift tools/make-dmg-background.swift build/dmg >/dev/null
tiffutil -cathidpicheck build/dmg/background.png build/dmg/background@2x.png \
    -out build/dmg/background.tiff >/dev/null

echo "→ Staging…"
rm -rf "$STAGE" "$RW_DMG" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp build/dmg/background.tiff "$STAGE/.background/background.tiff"
# Gatekeeper will stop an ad-hoc signed app on any Mac but this one, so the
# way past it travels with the image rather than in a covering message.
cp Resources/first-launch.txt "$STAGE/Если не открывается.txt"

# Room for the contents plus slack for the filesystem's own overhead.
SIZE_KB=$(du -sk "$STAGE" | cut -f1)
SIZE_MB=$(( SIZE_KB / 1024 + 40 ))

echo "→ Creating a writable image (${SIZE_MB} MB)…"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL" \
    -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RW_DMG"

echo "→ Mounting…"
MOUNT_DIR="/Volumes/$VOL"
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT_DIR" "$RW_DMG"
trap 'hdiutil detach -quiet "$MOUNT_DIR" 2>/dev/null || true' EXIT

echo "→ Arranging the window…"
if osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 860, 610}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP" of container window to {170, 190}
        set position of item "Applications" of container window to {490, 190}
        set position of item "Если не открывается.txt" of container window to {330, 330}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
then
    echo "  ✓ layout applied"
else
    echo "  ! Finder could not be scripted — the image will use the default layout."
    echo "    Grant the permission macOS just asked for, then run this script again."
fi

sync

echo "→ Unmounting…"
hdiutil detach -quiet "$MOUNT_DIR"
trap - EXIT

echo "→ Compressing…"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW_DMG"
rm -rf "$STAGE"

echo
echo "✓ $DMG  ($(du -h "$DMG" | cut -f1))"
echo
echo "  The app is ad-hoc signed, so the first launch on another Mac is blocked:"
echo "  open it once, then System Settings ▸ Privacy & Security ▸ Open Anyway."
