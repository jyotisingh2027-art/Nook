#!/bin/bash
# Builds Nook.app into the build/ folder (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

# Put the app together and sign it in a private temp folder: the Desktop may be
# synced by iCloud, which adds file labels that code signing refuses.
STAGE=$(mktemp -d)
APP_TMP="$STAGE/Nook.app"
mkdir -p "$APP_TMP/Contents/MacOS" "$APP_TMP/Contents/Resources"
cp .build/release/Nook "$APP_TMP/Contents/MacOS/Nook"
cp Resources/Info.plist "$APP_TMP/Contents/Info.plist"
if [ -d Resources/Wallpapers ]; then cp -R Resources/Wallpapers "$APP_TMP/Contents/Resources/Wallpapers"; fi
xattr -cr "$APP_TMP"
# Free "ad-hoc" signature so macOS will run it locally. No Apple account needed.
codesign --force --sign - "$APP_TMP" >/dev/null

APP=build/Nook.app
rm -rf "$APP"
mkdir -p build
ditto --noextattr "$APP_TMP" "$APP"
rm -rf "$STAGE"
echo "Built $APP"
