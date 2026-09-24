# AGENTS.md

This file gives coding agents the project-specific context needed to work safely in Sonexis. Human contributors should start with `README.md` and `CONTRIBUTING.md`.

## Project overview

Sonexis is a native macOS application that captures system audio through Core Audio Process Tap APIs, processes it through visual effect graphs, and sends the result to the selected output device. It supports a Default chain, independent app-specific chains, built-in effects, Audio Unit plug-ins, presets, recording, tutorials, and menu-bar controls.

The deployment target is macOS 14.4. The project is an Xcode project rather than a Swift Package.

## Start here

Before making a change, read the files relevant to its scope:

- `README.md` — setup, build, tests, and repository map.
- `CONTRIBUTING.md` — contribution rules and verification expectations.
- `docs/ARCHITECTURE.md` — runtime flow, ownership, and concurrency boundaries.
- `docs/MULTI-CHAIN-ENGINE.md` — app-specific routing design.
- `docs/PRODUCT-AND-ENGINE-ROADMAP.md` — product and engine decisions.

Release audits, evidence, handoff notes, and dated roadmap documents are historical records. Verify their date and compare them with current source before relying on them.

## Repository map

- `Sonexis/AudioEngine/` — graph rendering, effects, Audio Units, and recording.
- `Sonexis/ProcessTapEngine/` — system capture and device-output pipeline.
- `Sonexis/Models/` — graph, effect, plug-in, preset, and project models.
- `Sonexis/CanvasView/` — visual graph editor and effect controls.
- `Sonexis/ContentView/` — screens, workspace UI, onboarding, and tutorials.
- `Sonexis/SharedUI/` — shared design components.
- `Tests/` — standalone Swift regression harnesses.
- `Scripts/` — build, test, audit, and packaging tools.
- `External/rubberband/` — vendored GPL pitch-shifting dependency.

Put new code in the appropriate existing directory. Do not add replacement source files at the repository root.

## Working rules

- Keep changes tightly scoped to the request.
- Preserve unrelated working-tree changes; never reset or clean the repository unless explicitly asked.
- Do not redesign approved UI or change product behavior while performing cleanup or documentation work.
- Do not modify persisted formats without safe defaults, migration behavior, and regression coverage.
- Do not add dependencies without explaining their need, license, distribution impact, and maintenance cost.
- Do not edit vendored code under `External/` unless the task explicitly requires it.
- Never commit, tag, push, publish, package, sign, notarize, or change version numbers unless explicitly requested.
- Do not claim release readiness from a successful build or offline test run.

## Real-time audio constraints

Code reachable from an audio callback must not:

- allocate or resize collections;
- acquire contended locks or wait on another queue;
- perform file, preferences, discovery, or network access;
- log or synchronously publish UI state;
- call AppKit or SwiftUI;
- trust persisted or imported numeric values without validation.

Prepare immutable snapshots and reusable buffers outside callback time. Keep mutable DSP state isolated per chain, node, and channel as appropriate. Smooth parameter, bypass, and graph transitions when abrupt changes would create audible discontinuities. Preserve stereo linking or independence deliberately.

## Build

Use a repository-local Derived Data directory so test scripts can find the Debug product:

```sh
xcodebuild \
  -project Sonexis.xcodeproj \
  -scheme Sonexis \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

If sandboxed execution prevents Swift macro plug-ins from running, report that environmental failure or request the narrowly scoped permission needed to run `xcodebuild`. Do not change source code to work around a sandbox failure.

## Tests

Build the Debug app before running module-linked harnesses. Run the complete offline suite with:

```sh
Scripts/test-all.sh
```

For a focused change, run the relevant script during iteration and the broader affected suites before handoff. Typical mappings:

- persistence or models: preset and workspace persistence;
- graph/routing: compiled graph, graph transitions, and multichain;
- capture/lifecycle: capture target and audio lifecycle;
- recording: recording and combined recording;
- controls/tutorials: knob controls, tutorial, and chain workspace;
- DSP: focused signal tests plus graph, persistence, and variable-block coverage.

Tests should use synthetic audio and isolated temporary data. Never point destructive or malformed-input tests at the user's real presets or workspace.

## Manual and hardware boundaries

Do not start system-audio capture, play test tones, manipulate audio devices, launch the app for interactive UI testing, or perform sleep/wake tests unless the user explicitly requests that action. Offline tests do not verify live routing, device recovery, listening quality, sleep/wake behavior, signing, notarization, or installer acceptance.

For UI work, identify the exact manual checks the user should perform. For audible DSP changes, separate objective signal verification from level-matched listening verification.

## Code and documentation style

- Follow surrounding Swift conventions and use four-space indentation.
- Prefer small files and extensions grouped by responsibility.
- Name types and functions for domain intent.
- Comment invariants, ownership, and non-obvious DSP behavior rather than syntax.
- Avoid unrelated formatting churn.
- Add accessible labels and values to new interactive controls.
- Keep public documentation current when commands, structure, or compatibility change.
- Treat warnings introduced by a change as work to resolve.

## Completion checklist

Before reporting completion:

1. Review the final diff for accidental or unrelated changes.
2. Run `git diff --check`.
3. Build when source or project configuration changed.
4. Run tests proportional to the affected behavior.
5. State exactly what passed, what was not tested, and any manual checks still required.
6. Leave the decision to commit, release, or publish to the user unless they explicitly delegated it.
