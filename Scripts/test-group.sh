#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

run_test() {
    test_script=$1
    printf '\n==> %s\n' "$test_script"
    /bin/sh "$ROOT_DIR/Scripts/$test_script"
}

case "${1:-}" in
    lifecycle-capture)
        run_test test-audio-lifecycle.sh
        run_test test-background-window.sh
        run_test test-capture-target.sh
        ;;
    graph-routing)
        run_test test-compiled-graph.sh
        run_test test-graph-transition-integration.sh
        run_test test-audio-unit-lifecycle.sh
        run_test test-graph-transitions.sh
        run_test test-multichain.sh
        ;;
    dsp)
        run_test test-bitcrusher-safety.sh
        run_test test-pitch-continuity.sh
        ;;
    persistence-workspace)
        run_test test-chain-workspace.sh
        run_test test-preset-persistence.sh
        run_test test-workspace-persistence.sh
        ;;
    recording)
        run_test test-combined-recording.sh
        run_test test-recording.sh
        ;;
    ui-logic)
        run_test test-canvas-viewport.sh
        run_test test-knob-controls.sh
        run_test test-tutorial.sh
        ;;
    *)
        echo "Usage: $0 {lifecycle-capture|graph-routing|dsp|persistence-workspace|recording|ui-logic}" >&2
        exit 2
        ;;
esac
