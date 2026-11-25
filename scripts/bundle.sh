#!/bin/sh
# Builds EdifierBar.app (release) into ./build. A real .app bundle is required:
# macOS only grants Bluetooth access to apps with NSBluetoothAlwaysUsageDescription.
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product EdifierBar
BIN="$(swift build -c release --show-bin-path)/EdifierBar"
APP=build/EdifierBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/EdifierBar"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.edifierbar</string>
  <key>CFBundleName</key><string>EdifierBar</string>
  <key>CFBundleDisplayName</key><string>Edifier MR5</string>
  <key>CFBundleExecutable</key><string>EdifierBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Bluetooth is used to control the Edifier MR5 speaker.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
