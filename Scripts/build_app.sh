#!/bin/bash
# Builds "Tutor.app" (Apple Silicon, release) into ./dist
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Tutor.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tutor "$APP/Contents/MacOS/Tutor"

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift Scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Tutor</string>
  <key>CFBundleIdentifier</key><string>com.adamyap.tutor</string>
  <key>CFBundleName</key><string>Tutor</string>
  <key>CFBundleDisplayName</key><string>Tutor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.reference</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
