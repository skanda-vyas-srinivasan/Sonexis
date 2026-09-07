#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-recording-build.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sonexis/AudioEngine/AudioRecordingSession.swift" \
    "$ROOT_DIR/Tests/Recording/main.swift" -o "$TEST_DIR/recording-tests"
"$TEST_DIR/recording-tests"
