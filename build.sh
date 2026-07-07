#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LaViewer"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

swiftc -O \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    Sources/*.swift \
    -framework Cocoa -framework UniformTypeIdentifiers

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# App icon: icon.jpg (project root) -> AppIcon.icns
if [ -f icon.jpg ]; then
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" -s format png icon.jpg --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        dbl=$((size * 2))
        sips -z "$dbl" "$dbl" -s format png icon.jpg --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

codesign --force --deep --sign - "$APP_BUNDLE"

# Nudge Finder/Dock to drop any cached icon for this path
touch "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
