#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LastfmScrobbler"

APP="build/Last.fm Scrobbler.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/LastfmScrobbler"
cp Info.plist "$APP/Contents/Info.plist"

# App icon: build an .icns from the 1024px source PNG.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET" "$APP/Contents/Resources"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature with an identifier-based designated requirement, so macOS privacy
# permissions (Automation, Keychain) survive rebuilds instead of being tied to one binary hash.
codesign --force --sign - --identifier com.fr.LastfmScrobbler \
    -r='designated => identifier "com.fr.LastfmScrobbler"' "$APP"

echo "Built: $APP"
