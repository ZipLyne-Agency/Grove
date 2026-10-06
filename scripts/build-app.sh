#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Build and package the standalone macOS application.
# Generated build artifacts live outside the source repository.
OUTPUT="${GROVE_OUTPUT:-$HOME/Assets/grove/files}"
swift build -c release --product Grove
BIN="$(swift build -c release --show-bin-path)"
APP="$OUTPUT/Grove.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUTPUT/AppIcon.iconset"
swift scripts/make-icon.swift "$OUTPUT/icon_1024.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$OUTPUT/icon_1024.png" --out "$OUTPUT/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "$OUTPUT/icon_1024.png" --out "$OUTPUT/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$OUTPUT/AppIcon.iconset" -o "$OUTPUT/AppIcon.icns"
cp "$BIN/Grove" "$APP/Contents/MacOS/Grove"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>agency.ziplyne.grove</string>
<key>CFBundleName</key><string>Grove</string>
<key>CFBundleDisplayName</key><string>Grove</string>
<key>CFBundleExecutable</key><string>Grove</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 ZipLyne</string>
</dict></plist>
PLIST
if [[ -f "$OUTPUT/AppIcon.icns" ]]; then cp "$OUTPUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
