#!/bin/bash
# Builds MD Reader and installs it into /Applications.
#
# Launch Services keys a file association to the bundle's *path*, so an app that
# lives in a build folder loses .md the moment Xcode re-registers itself. After
# this script finishes, claim the association once from the app's File menu:
# "Make MD Reader the Default for Markdown…".
set -euo pipefail

cd "$(dirname "$0")"

APP="MD Reader.app"
DEST="/Applications/$APP"

./build.sh release

echo "→ Installing to $DEST…"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "→ Registering with Launch Services…"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST"

echo "→ Launching…"
open "$DEST"

echo
echo "✓ Installed. Now pick File ▸ “Make MD Reader the Default for Markdown…” once."
