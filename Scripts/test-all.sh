#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

for test_script in \
    test-audio-lifecycle.sh \
    test-background-window.sh \
    test-bitcrusher-safety.sh \
    test-canvas-viewport.sh \
    test-capture-target.sh \
    test-chain-workspace.sh \
    test-combined-recording.sh \
    test-compiled-graph.sh \
    test-graph-transition-integration.sh \
    test-graph-transitions.sh \
    test-knob-controls.sh \
    test-multichain.sh \
    test-pitch-continuity.sh \
    test-preset-persistence.sh \
    test-recording.sh \
    test-tutorial.sh \
    test-workspace-persistence.sh
do
    printf '\n==> %s\n' "$test_script"
    /bin/sh "$ROOT_DIR/Scripts/$test_script"
done

printf '\nAll Sonexis offline regression suites passed.\n'
