# Sonexis architecture

This document is a contributor map, not a complete API reference. It identifies the major ownership boundaries and the safest place to begin a change.

## Runtime flow

```text
macOS processes
      │
      ▼
Core Audio Process Tap
      │ captured PCM
      ▼
ProcessTapEngine ──► AudioEngine / graph snapshot ──► built-ins and Audio Units
      │                                                    │
      │                                                    ▼
      └──────────────────────────────────────────── processed PCM
                                                           │
                                    ┌──────────────────────┴─────────────┐
                                    ▼                                    ▼
                              output device                         WAV recorder
```

The Default chain handles audio not claimed by an enabled app-specific chain. An app-specific chain overrides Default for its selected process. Runtime processors are keyed by stable chain and node identifiers so presentation changes do not need to recreate unrelated audio pipelines.

## Source ownership

### Application and workspace

- `Sonexis/SonexisApp.swift` starts the app.
- `Sonexis/EditorWindowController.swift` owns editor-window lifecycle.
- `Sonexis/MenuBarController.swift` owns the menu-bar surface.
- `Sonexis/WorkspaceStore.swift` persists the multi-chain workspace.
- `Sonexis/PresetManager.swift` owns the preset library.

### Audio capture and output

`Sonexis/ProcessTapEngine/` wraps the macOS Process Tap and device-output pipeline. Lifecycle operations that can block belong off the main thread and must retain single ownership through cancellation and teardown.

### Graph and effects

`Sonexis/AudioEngine/` compiles graph state, routes buffers, hosts Audio Units, applies built-in effects, and records final output. UI-owned models are converted into processing snapshots before callback-time use. Stateful DSP must be scoped by node identity and cleared when nodes disappear.

### Models

`Sonexis/Models/` contains graph, effect, plug-in, preset, and project representations. Persisted types require backward-compatible decoding defaults. Treat values loaded from disk as untrusted and constrain them again at the DSP boundary.

### Editor UI

`Sonexis/CanvasView/` contains graph layout, wiring, node controls, drag/drop, and plug-in editor presentation. `Sonexis/ContentView/` contains the surrounding application screens, chain workspace, toolbar, presets, onboarding, and tutorials. Shared colors and components live in `Sonexis/SharedUI/`.

## Concurrency boundaries

- **Main thread:** SwiftUI/AppKit state, graph editing, and user interaction.
- **Audio lifecycle queue:** capture/output creation, start, stop, recovery, and teardown.
- **Real-time processing callback:** bounded buffer transformation only.
- **Recording writer queue:** disk I/O using buffers handed off by the callback.

Do not move data between these domains casually. Prefer immutable snapshots, stable IDs, bounded preallocated storage, and explicit ownership.

## Data and compatibility

- `Sonexis/StarterPresets.json` seeds built-in presets.
- Presets store reusable graph state.
- The workspace stores chains, selection, layout, and global audio settings.
- Audio Unit state is opaque third-party data and must be preserved even when a plug-in is unavailable.

Changes to these formats need migration/default behavior and persistence regression tests.

## Tests

Tests are standalone Swift harnesses under `Tests/`, invoked by matching scripts under `Scripts/`. Most link against `.build/DerivedData/Build/Products/Debug/Sonexis.app/Contents/MacOS/Sonexis.debug.dylib`, which is why the Debug build is a prerequisite.

The suites emphasize deterministic synthetic input, graph behavior, persistence isolation, lifecycle ownership, and failure boundaries. Hardware-dependent behavior still requires an explicit manual check and should not be reported as covered by an offline harness.
