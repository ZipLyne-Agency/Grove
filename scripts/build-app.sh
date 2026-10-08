#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Build and package the standalone macOS application.
# Generated build artifacts live outside the source repository.
OUTPUT="${GROVE_OUTPUT:-$HOME/Assets/grove/files}"
CONFIGURATION="${GROVE_CONFIGURATION:-release}"
JOBS="${GROVE_BUILD_JOBS:-4}"
[[ "$CONFIGURATION" == "release" || "$CONFIGURATION" == "debug" ]] || { echo "Invalid GROVE_CONFIGURATION" >&2; exit 1; }
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid GROVE_BUILD_JOBS" >&2; exit 1; }
if [[ "${GROVE_UNIVERSAL:-0}" == "1" ]]; then
  swift build -c "$CONFIGURATION" --jobs "$JOBS" --arch arm64 --arch x86_64 --product Grove
  BIN="$(swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)"
else
  swift build -c "$CONFIGURATION" --jobs "$JOBS" --product Grove
  BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"
fi
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
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 ZipLyne</string>
</dict></plist>
PLIST
if [[ -f "$OUTPUT/AppIcon.icns" ]]; then cp "$OUTPUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi
IDENTITY="${GROVE_SIGNING_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  rm -f "${APP:?}/Contents/embedded.provisionprofile"
  codesign --force --sign - "$APP"
else
  TEAM_ID="${GROVE_TEAM_ID:?Set GROVE_TEAM_ID to the Developer ID team identifier}"
  PROFILE="${GROVE_PROVISIONING_PROFILE:?Set GROVE_PROVISIONING_PROFILE to the matching Developer ID provisioning profile}"
  [[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid GROVE_TEAM_ID" >&2; exit 1; }
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  cat > "$OUTPUT/Grove.entitlements.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.application-identifier</key><string>$TEAM_ID.agency.ziplyne.grove</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM_ID</string>
</dict></plist>
PLIST
  codesign --force --options runtime --timestamp --entitlements "$OUTPUT/Grove.entitlements.plist" --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP"
