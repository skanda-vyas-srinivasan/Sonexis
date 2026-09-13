#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonexis-workspace-build.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" \
    "$ROOT_DIR/Sonexis/Models/EffectType.swift" \
    "$ROOT_DIR/Sonexis/Models/PluginReference.swift" \
    "$ROOT_DIR/Sonexis/Models/NodeEffectParameters.swift" \
    "$ROOT_DIR/Sonexis/Models/GraphNode.swift" \
    "$ROOT_DIR/Sonexis/Models/GraphSnapshot.swift" \
    "$ROOT_DIR/Sonexis/Models/GraphLoadRequest.swift" \
    "$ROOT_DIR/Sonexis/Models/PluginModels.swift" \
    "$ROOT_DIR/Sonexis/PresetManager.swift" \
    "$ROOT_DIR/Sonexis/WorkspaceStore.swift" \
    "$ROOT_DIR/Tests/WorkspacePersistence/main.swift" -o "$TEST_DIR/workspace-tests"
"$TEST_DIR/workspace-tests"
