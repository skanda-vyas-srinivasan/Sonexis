#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-canvas-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sonexis/CanvasView/CanvasViewportLayout.swift" \
    "$ROOT_DIR/Tests/CanvasViewport/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests" "$ROOT_DIR/Sonexis/StarterPresets.json"
