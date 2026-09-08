#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-latency-probe.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -O2 -I "$ROOT_DIR/Sonexis/ProcessTapEngine" \
    "$ROOT_DIR/Sonexis/ProcessTapEngine/RealtimeAudioRing.c" \
    "$ROOT_DIR/Tests/LatencyProbe/main.c" -o "$TEST_DIR/latency-probe"
"$TEST_DIR/latency-probe"
