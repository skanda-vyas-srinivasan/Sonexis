#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DERIVED_DATA="$ROOT_DIR/.build/DerivedDataTSan"
PRODUCTS="$DERIVED_DATA/Build/Products/Debug"
BINARY_DIR="$PRODUCTS/Sonexis.app/Contents/MacOS"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-tsan.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

xcodebuild \
    -project "$ROOT_DIR/Sonexis.xcodeproj" \
    -scheme Sonexis \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    -enableThreadSanitizer YES \
    build

run_tsan_harness() {
    name=$1
    source=$2
    executable="$TEST_DIR/$name"
    module_cache="$TEST_DIR/$name-module-cache"

    xcrun swiftc -sanitize=thread \
        -module-cache-path "$module_cache" \
        -I "$PRODUCTS" \
        "$source" \
        "$BINARY_DIR/Sonexis.debug.dylib" \
        -o "$executable"

    DYLD_LIBRARY_PATH="$BINARY_DIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
        "$executable"
}

run_tsan_harness \
    graph-transition-integration \
    "$ROOT_DIR/Tests/GraphTransitionIntegration/main.swift"
run_tsan_harness \
    audio-unit-lifecycle \
    "$ROOT_DIR/Tests/AudioUnitLifecycle/main.swift"

printf '\nAll focused Thread Sanitizer checks passed.\n'
