#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PRODUCTS="$ROOT_DIR/.build/DerivedData/Build/Products/Debug"
BINARY_DIR="$PRODUCTS/Sonexis.app/Contents/MacOS"
# Requires the current Debug app build.
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-knob-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" -I "$PRODUCTS" \
    "$ROOT_DIR/Tests/KnobControls/main.swift" \
    "$BINARY_DIR/Sonexis.debug.dylib" -o "$TEST_DIR/knob-tests"
DYLD_LIBRARY_PATH="$BINARY_DIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$TEST_DIR/knob-tests"
