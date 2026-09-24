# Contributing to Sonexis

Thank you for helping improve Sonexis. This guide describes the path from an idea or defect to a reviewable change.

## Before you start

- Search existing issues before opening a new one.
- Use an issue to discuss substantial features, UX changes, new effects, persistence changes, or audio-routing changes before implementation.
- Small fixes, documentation improvements, and focused test additions may go directly to a pull request.
- Keep changes narrow. Avoid combining cleanup, visual redesign, and behavior changes in one pull request.

## Development setup

You need macOS 14.4 or later and Xcode 16 or later with a compatible macOS SDK. Clone the repository normally; all required source dependencies are vendored.

Build a testable Debug product:

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

Then run:

```sh
Scripts/test-all.sh
```

CI reports the same coverage as separate functional checks for lifecycle and capture, graph and routing, DSP, persistence and workspace, recording, and UI logic. To run one group locally, use `Scripts/test-group.sh <group>`; running `Scripts/test-group.sh` without an argument prints the available group names.

The standalone test executables import and link the Debug application module. If the compiler reports that the module was produced by another Swift version, rebuild the Debug app with the active Xcode installation before rerunning the scripts.

## Design boundaries

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing capture, routing, graph processing, persistence, or window lifecycle behavior.

### Real-time audio rules

Code reachable from an audio callback must not:

- allocate or resize collections;
- acquire contended locks or wait on another queue;
- access files, preferences, plug-in discovery, or other external services;
- log or synchronously publish UI state;
- call AppKit or SwiftUI;
- accept unbounded or non-finite persisted values.

Prepare immutable snapshots and reusable buffers outside the callback. Keep DSP state isolated per effect node and channel. Parameter changes and bypass transitions should be smoothed when discontinuities would be audible.

### Persistence compatibility

Presets and workspaces are user data. When adding or changing a persisted field:

- provide safe decoding defaults for older files;
- preserve stable identifiers or add an explicit migration;
- test save/load, import/export, duplicate, and corruption behavior as applicable;
- do not silently rewrite unrelated settings.

### User interface changes

- Preserve keyboard and accessibility behavior.
- Check narrow and wide window layouts.
- Use the existing design system and all supported themes.
- Avoid adding explanatory text where layout and state can communicate clearly.
- Include before/after images for visible changes when practical.

## Testing expectations

Choose tests based on risk, not file count.

| Change | Minimum verification |
| --- | --- |
| Documentation only | Links, commands, and Markdown reviewed locally |
| Model or persistence | Relevant preset/workspace suite |
| Graph or routing | Compiled graph, transitions, and multichain suites |
| DSP/effect | Focused signal tests plus graph and persistence regressions |
| Capture/lifecycle | Capture target and audio lifecycle suites |
| UI behavior | Debug build, focused harness, and manual app check |
| Recording | Recording and combined-recording suites |

Do not play test tones, capture live audio, modify real user data, sign, notarize, or package an installer as part of an ordinary automated test run.

## Code style

- Follow the surrounding Swift style and use four-space indentation.
- Prefer small types and extensions grouped by responsibility.
- Use names that describe domain intent rather than implementation trivia.
- Comment invariants and non-obvious audio behavior, not syntax.
- Avoid unrelated formatting changes.
- Treat compiler warnings introduced by a change as failures to resolve.

## Pull requests

A good pull request includes:

- a concise problem statement and the chosen solution;
- the affected user workflow;
- test commands and their results;
- compatibility or migration notes;
- screenshots for visible changes;
- known limits or checks that require hardware/manual verification.

### Classification and review depth

Pull requests are labeled automatically from their changed paths. Area labels identify the affected subsystem; `validation:` labels identify checks that automation cannot complete; and `risk: elevated` flags changes involving audio processing, capture, persisted data, permissions, dependencies, or project configuration.

Path labels are a review aid, not a substitute for judgment. In the pull request template, write one overall risk level as `Risk level: Low`, `Risk level: Medium`, or `Risk level: High`, and describe any mismatch between the automatic labels and the actual behavior change. Contributors should report the manual checks they performed and explicitly list relevant scenarios they could not test.

Changes carrying `validation: manual-audio`, `validation: manual-ui`, `validation: migration-review`, or `validation: security-review` require the corresponding maintainer review before release. Code ownership automatically requests maintainer review for the most sensitive paths when code-owner reviews are enabled in the repository ruleset.

By contributing, you agree that your contribution is licensed under GPL-2.0-or-later, the same terms as the project.
