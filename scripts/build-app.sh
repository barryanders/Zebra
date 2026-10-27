#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native -c release
BIN_DIR="$(swift build --build-system native -c release --show-bin-path)"
APP="dist/Zebra.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TechnicolorZebra" "$APP/Contents/MacOS/TechnicolorZebra"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TechnicolorZebra</string>
<key>CFBundleIdentifier</key><string>io.github.barryanders.daylight</string>
<key>CFBundleName</key><string>Zebra</string>
<key>CFBundleDisplayName</key><string>Zebra</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleIconFile</key><string>TechnicolorZebra</string>
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
cp Assets/zebra-icon.png "$APP/Contents/Resources/Zebra.png"
swift scripts/make-icon.swift "$APP/Contents/Resources/TechnicolorZebra.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/Zebra-$(uname -m).zip"
echo "Built $APP"
