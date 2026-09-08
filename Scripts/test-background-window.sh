#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-window-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sonexis/EditorWindowController.swift" \
    "$ROOT_DIR/Tests/BackgroundWindow/main.swift" -o "$TEST_DIR/window-tests"
"$TEST_DIR/window-tests"
