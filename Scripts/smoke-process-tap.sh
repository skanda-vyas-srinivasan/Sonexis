#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/Sonexis.app/Contents/MacOS/Sonexis"
LOG_FILE=$(mktemp "${TMPDIR:-/tmp}/sonexis-processtap-smoke.XXXXXX")

cd "$ROOT_DIR"
xcodebuild \
    -project Sonexis.xcodeproj \
    -scheme Sonexis \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'platform=macOS' \
    build \
    CODE_SIGNING_ALLOWED=NO

SONEXIS_PROCESS_TAP_SMOKE=1 "$APP" >"$LOG_FILE" 2>&1
cat "$LOG_FILE"

grep -F "Sonexis Process Tap smoke test started." "$LOG_FILE" >/dev/null
grep -F "Started Process Tap -> unity passthrough DSP -> default output playback." "$LOG_FILE" >/dev/null
grep -F "Pitch shift: enabled=false" "$LOG_FILE" >/dev/null
grep -F "Shutdown complete. Normal system audio should be restored." "$LOG_FILE" >/dev/null
grep -F "Sonexis Process Tap smoke test stopped." "$LOG_FILE" >/dev/null

echo "Sonexis Process Tap smoke test passed."
