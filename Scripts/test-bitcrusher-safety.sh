#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PRODUCTS="$ROOT_DIR/.build/DerivedData/Build/Products/Debug"
BINARY_DIR="$PRODUCTS/Sonexis.app/Contents/MacOS"
# Requires a fresh Debug build; runs offline and uses only temporary storage.
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-bitcrusher-safety.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" -I "$PRODUCTS" \
    "$ROOT_DIR/Tests/BitcrusherSafety/main.swift" \
    "$BINARY_DIR/Sonexis.debug.dylib" -o "$TEST_DIR/bitcrusher-tests"
DYLD_LIBRARY_PATH="$BINARY_DIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$TEST_DIR/bitcrusher-tests" "$ROOT_DIR"
