#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-tutorial.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sonexis/ContentView/TutorialTypes.swift" \
    "$ROOT_DIR/Sonexis/ContentView/TutorialController.swift" \
    "$ROOT_DIR/Tests/Tutorial/main.swift" -o "$TEST_DIR/tutorial-tests"
"$TEST_DIR/tutorial-tests"
