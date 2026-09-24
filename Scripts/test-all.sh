#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

for test_group in \
    lifecycle-capture \
    graph-routing \
    dsp \
    persistence-workspace \
    recording \
    ui-logic
do
    printf '\n==== %s ====\n' "$test_group"
    /bin/sh "$ROOT_DIR/Scripts/test-group.sh" "$test_group"
done

printf '\nAll Sonexis offline regression suites passed.\n'
