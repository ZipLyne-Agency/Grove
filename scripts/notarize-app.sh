#!/bin/bash
set -euo pipefail
# Credentials belong to the caller's secret broker, never to this repository.
APP="${1:?Usage: notarize-app.sh /path/to/Grove.app}"
: "${NOTARY_API_KEY_FILE:?Set NOTARY_API_KEY_FILE to a protected temporary .p8 file}"
: "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}"
: "${NOTARY_ISSUER:?Set NOTARY_ISSUER}"
OUTPUT="$(dirname "$APP")"
ARCHIVE="$OUTPUT/Grove-notary.zip"
VERSION="$(/usr/libexec/PlistBuddy -c Print:CFBundleShortVersionString "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid app version" >&2; exit 1; }
ZIP="$OUTPUT/Grove-$VERSION-macOS.zip"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --key "$NOTARY_API_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait --timeout 5m --output-format json
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
rm -f "${ARCHIVE:?}"
shasum -a 256 "$ZIP"
