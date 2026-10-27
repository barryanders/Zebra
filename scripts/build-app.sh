#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native -c release
BIN_DIR="$(swift build --build-system native -c release --show-bin-path)"
APP="dist/Daylight.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Daylight" "$APP/Contents/MacOS/Daylight"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Daylight</string>
<key>CFBundleIdentifier</key><string>io.github.barryanders.daylight</string>
<key>CFBundleName</key><string>Daylight</string>
<key>CFBundleDisplayName</key><string>Daylight</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>Daylight</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Video</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>CFBundleTypeExtensions</key><array><string>mkv</string><string>mov</string><string>mp4</string><string>m4v</string><string>ts</string><string>m2ts</string></array>
</dict></array>
</dict></plist>
PLIST
swift scripts/make-icon.swift "$APP/Contents/Resources/Daylight.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/Daylight-$(uname -m).zip"
echo "Built $APP"
