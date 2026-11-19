#!/bin/bash
# Builds Nook.app into the build/ folder (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Nook.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Nook "$APP/Contents/MacOS/Nook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -d Resources/Wallpapers ]; then cp -R Resources/Wallpapers "$APP/Contents/Resources/Wallpapers"; fi
# Free "ad-hoc" signature so macOS will run it locally. No Apple account needed.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
