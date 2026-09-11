#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT_DIR="$ROOT_DIR/.build/LiveAcceptance"
BIN="$OUT_DIR/ToneApp"
mkdir -p "$OUT_DIR"
xcrun swiftc "$ROOT_DIR/Tests/LiveAcceptance/ToneApp.swift" \
    -framework AppKit -framework AVFoundation -o "$BIN"

make_app() {
    name=$1
    bundle_id=$2
    frequency=$3
    amplitude=${4:-0.00005}
    app="$OUT_DIR/$name.app"
    mkdir -p "$app/Contents/MacOS"
    cp "$BIN" "$app/Contents/MacOS/ToneApp"
    /usr/libexec/PlistBuddy -c "Clear dict" \
        -c "Add :CFBundleExecutable string ToneApp" \
        -c "Add :CFBundleIdentifier string $bundle_id" \
        -c "Add :CFBundleName string $name" \
        -c "Add :CFBundlePackageType string APPL" \
        -c "Add :ToneFrequency real $frequency" \
        -c "Add :ToneAmplitude real $amplitude" \
        "$app/Contents/Info.plist"
    codesign --force --sign - "$app"
}

make_app "Sonexis Tone A" "com.sonexis.acceptance.tone-a" 330
make_app "Sonexis Tone B" "com.sonexis.acceptance.tone-b" 550
make_app "Sonexis Tone Default" "com.sonexis.acceptance.tone-default" 770
make_app "Sonexis Recording Verify" "com.sonexis.acceptance.recording-verify" 990
echo "Built four signed local tone apps in $OUT_DIR"
