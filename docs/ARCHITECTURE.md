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

`AudioEngine` is the main-thread `ObservableObject` facade. It owns published UI state, device and pipeline orchestration, editable graph models, graph validation, routing-plan compilation, and processing-snapshot publication. It does not own mutable DSP dictionaries or graph-rendering buffers.

`AudioGraphProcessor` is the single processing-worker owner. It owns per-node DSP state, graph execution, reusable worker buffers, graph-output transitions, DSP fault counters, and the prepared plug-in render-state references embedded in each snapshot. Graph edits publish immutable processing snapshots plus bounded reset and node-retirement commands. The worker consumes them at block boundaries. Main-thread code must not inspect, mutate, or release worker-owned DSP objects.

### Audio Unit handoff

Audio Unit lifecycle work is separate from live rendering. Each `AUPluginInstance` serializes preparation requests, and each request creates a distinct `AUPreparedRenderState`. Instantiation, persisted-state loading, format negotiation, render-resource allocation, scratch allocation, and warm-up all finish before that state can be published. The processing worker never performs those operations and never acquires the plug-in lifecycle, UI, editor, or state-serialization locks.

A completed state becomes eligible for rendering only when `AudioEngine` includes its retained reference in a new immutable `ProcessingSnapshot`. That snapshot is acquired at a block boundary. An in-flight block retains its snapshot, so replacing or removing a plug-in cannot destroy the state it is using. Final third-party state release is deferred to a utility lifecycle queue instead of running on the processing worker. A failed preparation keeps the previous prepared state published when one exists; without a prepared state, the graph follows its existing dry/bypassed behavior and the failure is exposed through plug-in status.

Parameter writes use the Audio Unit parameter API against the currently published generation. State loading does not mutate that generation; it prepares a replacement Audio Unit and uses the same snapshot handoff. Editor and state-serialization access may be slow inside third-party code, but Sonexis does not hold a render-path lock while they run. VST3 metadata can still be decoded for compatibility, but Sonexis does not create a no-op runtime processor for that unsupported format.

### Models

`Sonexis/Models/` contains graph, effect, plug-in, preset, and project representations. Persisted types require backward-compatible decoding defaults. Treat values loaded from disk as untrusted and constrain them again at the DSP boundary.

### Editor UI

`Sonexis/CanvasView/` contains graph layout, wiring, node controls, drag/drop, and plug-in editor presentation. `Sonexis/ContentView/` contains the surrounding application screens, chain workspace, toolbar, presets, onboarding, and tutorials. Shared colors and components live in `Sonexis/SharedUI/`.

## Concurrency boundaries

- **Main thread:** SwiftUI/AppKit state, graph editing, and user interaction.
- **Audio lifecycle queue:** capture/output creation, start, stop, recovery, and teardown.
- **Audio Unit lifecycle queues:** one serial preparation coordinator per hosted unit. These queues construct replacement render generations and never run graph rendering.
- **Process Tap callback:** bounded buffer handoff only. It does not render the graph.
- **Processing worker:** graph rendering and exclusive mutation of processing buffers and per-node DSP state. It consumes immutable graph snapshots and bounded commands at block boundaries.
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
