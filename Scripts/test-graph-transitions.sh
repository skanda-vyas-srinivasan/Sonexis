#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-transition-build.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sonexis/AudioEngine/GraphOutputTransition.swift" \
    "$ROOT_DIR/Tests/GraphTransitions/main.swift" -o "$TEST_DIR/transition-tests"
"$TEST_DIR/transition-tests"
