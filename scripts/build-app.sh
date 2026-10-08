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
mkdir -p "$OUTPUT"
python3 scripts/package-app.py "$BIN/Grove" "$OUTPUT"
