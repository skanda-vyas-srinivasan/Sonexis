# Sonexis product and engine working plan

Updated: 2026-09-06
Baseline: commit `4dc91ac`, plus the existing working tree reviewed in this session
Status: active backlog; save-reliability implementation recorded in section 11
Owner: unassigned per item

## 1. Purpose and review limits

Make Sonexis easier to use every day while retaining its expressive effects canvas. Prioritize reliable playback, recoverable work, understandable controls, and useful listening outcomes. Develop per-app chains as a potential major feature after validating the capture and mixing architecture.

This document records a source-based review of SwiftUI screens, navigation, graph execution, Process Tap capture/playback, recording, presets, and Audio Unit hosting. It is not a listening test, visual assessment of a running build, performance benchmark, or completed compatibility audit. Buffer-derived latency estimates are not measured end-to-end latency.

Evidence labels used below:

- **Observed:** behavior directly represented in the inspected code.
- **Risk:** plausible runtime consequence that needs reproduction or profiling.
- **Proposal:** intended product or implementation change, not current functionality.

Keep implementation status separate from evidence confidence. A source finding is not a completed fix.

## 2. Product direction

The desired experience is: open Sonexis, choose what should sound better, hear a useful result, and adjust it without worrying about losing work or breaking playback.

Preserve the existing strengths: automatic and manual wiring, parallel branches, stereo/dual-mono graphs, undo/redo, multiselection, effect search and favorites, exact numeric parameter entry, Audio Unit discovery/editors, recording, and route/sleep recovery infrastructure.

Provide two complementary surfaces:

- **Listening view:** source/app, preset, a few macro controls, output state, and effects bypass.
- **Chain editor:** the existing canvas, with clear editing affordances and contextual advanced routing controls.

Per-app processing should eventually fit the same model: select an app, choose a chain, then edit that chain in the familiar editor.

## 3. Priority and execution rules

| Priority | Meaning | Release expectation |
| --- | --- | --- |
| P0 | Playback truthfulness, work preservation, recording correctness | Address before expanding routing |
| P1 | Core workflow, continuity, predictable processing | Main next development phase |
| P2 | Product expansion and advanced audio capabilities | Build after prerequisites and experiments |
| P3 | Optional polish or later scope | Revisit against usage evidence |

Items start as **Proposed** with **Owner: unassigned**; section 11 records subsequent changes. Findings describe the original reviewed baseline unless a completion note says otherwise. When starting an item, record its owner, issue/PR, reproduction evidence, decisions, and completion evidence in section 11. Do not close an item on implementation alone; its acceptance checks must pass.

Effort descriptions are relative, not delivery commitments. Per-app routing is a substantial architectural feature and needs a bounded feasibility experiment before scheduling a full implementation.

## 4. UX/UI backlog

### UX-01 — Expose and unify the preset library · P0

**Observed:** `PresetView` contains management and import/export, but the inspected navigation contains no assignment opening `.presets`. The header opens `LoadPresetDialog`, a separate and more limited browser.

**Change:** Introduce a persistent preset selector with the current preset name, modified indicator, Browse presets, Save, Save as, and Revert. Route Browse to the existing library or consolidate the library into one reusable surface. Avoid maintaining two conflicting preset experiences.

**Acceptance:** The normal build screen can reach import, export, rename, delete, search, and apply. Save versus Save as is clear. Empty library and no search results have different messages and useful actions. Keyboard navigation works. Loading preserves a recoverable prior workspace.

**Evidence:** `Sonexis/ContentView/ContentView.swift`, `HeaderView.swift`, `LoadPresetDialog.swift`, `PresetView.swift`.

### UX-02 — Useful first launch and session restoration · P1

**Observed:** `ContentView` starts on Home; Home presents “Click anywhere to start.” Current preset identity and navigation snapshots are view state. No persisted workspace restoration was found in the inspected paths.

**Change:** First launch offers a small set of listening goals and Build your own. Returning launches restore the last workspace. Keep welcome animation optional. Autosave workspace state separately from user-named presets, including the current graph, selection-independent layout, source assignment, and modified status.

**Acceptance:** Relaunch restores an unsaved graph without overwriting a saved preset. Failed restoration preserves the source data and offers recovery. Users can choose whether processing starts automatically; restoring a workspace does not silently imply permission to change that preference. A clean first launch reaches useful processing in a short, documented flow.

**Dependencies:** DATA-01; later APP-01 routing schema.

### UX-03 — Explain playback and bypass states · P0

**Observed:** Power and effects bypass are icon-heavy. Bypass uses the same symbol in both states. The running route label is “Process Tap,” and the backend sets a generic “Default Output” name.

**Change:** Use explicit state text: Starting, Processing, Effects bypassed, Waiting for audio, Reconnecting, No output device, Stopped, and Failed. Display the actual device. Put concise recovery actions beside failures; technical diagnostics belong in a details view.

**Acceptance:** Every backend lifecycle transition produces the corresponding UI state. Effects bypass remains distinguishable from stopped capture. Users can identify selected source and actual output without opening diagnostics. Color is not the sole state indicator. A failed route rebuild cannot leave a healthy running indicator.

**Dependencies:** ENG-02.

### UX-04 — Simplify everyday controls · P1

**Decision — 2026-09-07:** Skip the separate listening screen. The user agrees that preset selection, power, bypass, and a meter do not justify another screen alongside the existing editor. Revisit these controls as a menu-bar popover under UX-08; no implementation is authorized by this decision.

**Remaining ideas:** In the canvas, expose manual wiring controls contextually. Move Flow FPS into appearance/performance preferences. Discuss these separately before implementation.

**Acceptance:** Everyday controls remain accessible without adding a separate listening screen. A future menu-bar popover shares the editor's audio state and does not rebuild an unchanged graph.

### UX-05 — Discoverable and reversible graph editing · P1

**Observed:** Double-click opens effects; manual connection uses Option-drag. Disconnected tiles are dimmed. Switching to Manual clears `manualConnections`.

**Change:** Add visible connection ports and an edit affordance for selection. Provide a plain “Not connected” explanation and suggested connection action. Per the user's decision, convert the current automatic edges into manual wires when entering Manual. Do not remember a separate previous manual topology. Record mode changes as undoable graph edits.

**Acceptance:** Users can connect and edit without a tutorial. Automatic → Manual preserves the current automatic connections and wire gains, including both populated split lanes. Empty lanes pass audio without a generated manual wire. Manual → Automatic resumes position-based routing; switching back converts that current routing. Undo restores topology and audio behavior. Invalid cycles or unsupported graph structures have clear handling. Deleting a connected node produces a predictable, documented result.

**Evidence:** `Sonexis/CanvasView/CanvasView.swift`, `EffectBlockHorizontal.swift`.

**Wiring conversion implemented — 2026-09-07:** Selecting Manual copies the current generated connections, including gain overrides and both populated split lanes, into editable manual wires. Selecting Automatic uses position-based routing as before. Switching back to Manual converts that current automatic routing; no separate remembered manual topology is restored. Menu mode changes record an undo snapshot, and snapshot restoration does not rerun conversion. Tutorial wording now explains that the wires are retained. Debug build and whitespace checks passed; interactive conversion/undo checks remain manual. Other UX-05 affordances remain separate.

**Entering Dual Mono — 2026-09-07:** Per user preference, switching from Stereo to Dual Mono clears all nodes, manual wires, gain overrides, and selection instead of dividing the existing chain by canvas position. The wiring mode remains selected; Automatic generates empty-lane passthrough. This is one undoable graph-mode change. Selecting the already active mode does nothing. Loading a saved split graph or restoring one through undo/session recovery preserves its nodes; clearing applies only to the explicit mode-menu action. Returning to Stereo retains the current behavior.

### UX-06 — Readability and accessible parameter editing · P1

**Parameter controls implemented — 2026-09-07:** Built-in effect knobs support Shift-drag at one-tenth sensitivity, Option-click reset, a right-click Reset to Default action, and focused arrow-key adjustment (Up/Right increase, Down/Left decrease; Shift uses a finer step). Every knob receives its parameter's canonical default, including individual EQ bands. A subtle focus ring identifies the keyboard target. VoiceOver adjustment and reset actions use the same value setter. Typed numeric entry remains; readouts expose the precision needed for fine steps. Native plugin-owned editors are outside this change.

Drag motion accumulates unrounded deltas, so switching Shift mid-drag does not reinterpret earlier motion or jump the value, and fine integer drags do not stall. Keyboard steps use displayed units; integer knobs always step by one. Values are clamped and non-finite typed values rejected. Debug build and `sh Scripts/test-knob-controls.sh` pass, covering sensitivity/modifier changes, bounds/reversal, integer accumulation, key-step units, typed precision, and invalid values. Pointer/focus/VoiceOver interaction remains a manual verification step.

**Observed:** Effect names use 10-point text with further scaling; several labels use 9–11 points. Knobs have exact numeric entry and accessibility labels/values, but their main adjustment is a drag gesture.

**Change:** Increase important label sizes, reduce text glow, and reserve strong accents for selection and meaningful state. Add fine adjustment, reset-to-default, keyboard adjustment, focus indicators, and accessibility adjustment actions. Retain exact typed values.

**Acceptance:** Important labels remain legible at supported window sizes and themes. Long plugin names remain identifiable. VoiceOver can identify and adjust parameters. Keyboard users can add, select, edit, bypass, and remove an effect. Reduce Motion applies to decorative animation throughout the app. Validate these in a running build; source inspection alone cannot establish contrast or layout quality.

### UX-07 — Contextual onboarding · P2

**Observed:** Basics walks through many controls, including settings and preset operations, with tutorial-specific locking.

**Change:** Initial lesson: enable audio, choose a sound, adjust it, compare bypass. Offer short contextual lessons for wiring, parallel chains, recording, and per-app assignments. Preserve the user's workspace around tutorials.

**Acceptance:** Tutorials can be skipped and reopened. Ending or interrupting a lesson restores prior work. Tutorial advancement depends on successful actions, including successful engine start and preset persistence.

### UX-08 — Background operation and Dock reopening · P1

**Original issue:** Closing the last window terminated the app and stopped processing.

**Decision — 2026-09-08:** Keep the app running when the editor closes; reopen through the Dock. No menu-bar icon or close-behavior preference for this pass. A separate quick-control surface is unnecessary for the agreed workflow. Explicit Quit/Command-Q still exits and stops processing. Login launch remains separate.

**Acceptance:** The red close button and Command-W hide the editor while processing continues. Clicking the Dock icon reopens the same editor, including from a minimized state, without creating another engine. Quit reliably releases capture and restores normal output. Workspace persistence runs on hide and quit.

## 5. Engine and recording backlog

### ENG-01 — Continuous graph changes · P1

**Observed:** `applyGraphChangeCrossfade` zeros output for approximately 20 ms and then fades in over approximately 120 ms. This path does not mix old and new graph output.

**Change:** Prepare changes outside processing, preserve unchanged state, and transition old/new outputs with independent effect state where both must render. Define tail handling when removing delay/reverb and latency alignment when graph delay changes. Handle simple gain/bypass changes through smoothing where possible.

**Acceptance:** Sustained-tone and music tests show no inserted silent region from ordinary edits. Reordering, deleting, bypassing, and loading presets have bounded transitions without unintended gain spikes. Old and new renders do not advance the same stateful instance twice. Stress graph changes while recording.

**Evidence:** `Sonexis/AudioEngine/IO.swift`.

### ENG-02 — One authoritative engine lifecycle · P0

**Observed:** The backend implements route changes, device-alive monitoring, sleep/wake handling, teardown, and retry logic. Some terminal recovery failures are logged without a lifecycle callback updating `AudioEngine.isRunning`.

**Change:** Introduce typed state events and errors between `ProcessTapDSPApp` and the UI-facing engine. Represent starting, preroll, running, recovering, waiting for a device, stopping, and failed. Keep requested operation separate from actual running state. Attach recovery actions to typed failures rather than string matching.

**Acceptance:** Initial failure, unplug, no default output, exhausted retries, sleep/wake, and stop-during-recovery produce correct state. Stale asynchronous completions cannot revive an old pipeline. Teardown is idempotent. A user can retry without relaunching. Normal source playback is restored after failure and quit.

**Evidence:** `Sonexis/ProcessTapEngine/ProcessTapDSPApp.swift`, `Sonexis/AudioEngine/ProcessTapBackend.swift`.

### ENG-03 — Latency profiles and telemetry · P1

**Decision — 2026-09-08:** User is satisfied with the current 4,096-frame buffer and does not consider latency a bottleneck. Defer buffer reduction and latency-profile implementation. Retain the investigation for future reference; no smaller-buffer trial is planned now.

**Investigation — 2026-09-08:** See [latency investigation](LATENCY-INVESTIGATION.md). Confirmed the 4,096-frame target and measured synthetic stall tolerance using the actual C ring implementation. A 2,048-frame target is a candidate for an opt-in trial, not a validated default. The worker does not wait for a full 1,024-frame chunk. Hardware loopback, scheduling/DSP timing, and live stability checks remain outstanding. No product latency setting was changed.

**Observed:** Playback reservoir target is 4,096 frames: 85.3 ms at 48 kHz or 92.9 ms at 44.1 kHz. Actual delay includes device, scheduling, effect, and other buffering contributions. Two seconds of ring capacity is capacity, not a claim of normal two-second latency.

**Change:** Measure delay with loopback/impulse tests; expose a derived estimate with its limitations. Prototype Low Latency and Stable profiles with bounded fill targets. Collect processing duration, fill level, input/output drops, and recovery counts. Evaluate the current one-frame consume adjustment and interpolation under clock drift.

**Acceptance:** Record device, sample rate, profile, chain, measured delay, and dropout counts. Validate video and interactive use. Do not lower the buffer solely to produce a better displayed number. Profile switches have defined transitions and no stale buffered audio.

**Evidence:** `ProcessTapDSPApp.swift`, `ProcessTapProcessingWorker.swift`, `RealtimeAudioRing.c`.

### ENG-04 — Compile graphs and bound processing work · P1

**Routing-plan scope implemented — 2026-09-08:** Prepare and cache immutable manual/left/right routing plans during main-thread snapshot publication. The worker reuses their ordered effect steps and input/output edges. Parameter, bypass, position-only and transient wire-ID changes reuse plans; changed routing/gains/endpoints/auto-connect settings rebuild the affected plan. The existing automatic serial-chain path stays intact. Broader buffer-allocation, lock-contention and lifetime work remains separate.

**Observed:** `processGraph` rebuilds edge/traversal data each block and allocates merge buffers. Shared locks and nested Swift arrays exist in the worker processing path. Some helpers reallocate when frame length changes rather than only when capacity grows. Hardware callbacks are already lightweight and backed by C ring buffers.

**Risk:** Allocation, copying, lock contention, and scheduling variability may contribute to underruns under load. This is a profiling hypothesis, not a measured finding.

**Change:** Compile topology on mutation; maintain ordered nodes, indexed input edges, preallocated scratch, and explicit capacities. Separate graph configuration from DSP state. Use bounded publication of parameters and prepared graph versions. Move logging/diagnostic formatting out of deadline-sensitive work. Audit the lifetime of retired graphs and plugin instances.

**Acceptance:** Profile allocations and worst-case processing time for fixed and varying block sizes. Topology is not rebuilt per block. Idle UI changes do not affect processing. Benchmarks cover serial/parallel graphs, multiple plugins, recording, and eventually multiple app chains. Keep the existing ring-buffer isolation unless measurements justify a different architecture.

### ENG-05 — Branch latency compensation · P1 prerequisite for advanced routing

**Observed:** Branch buffers are directly summed; the plugin interface does not expose processing latency. No branch compensation was found.

**Change:** Add declared latency to processors, compute cumulative arrival delay at each merge, and delay shorter paths before summing. Read Audio Unit latency where supported; define handling for unknown or changing latency. Compensate algorithmic latency, not intentional echoes/reverb tails.

**Acceptance:** Impulse alignment is verified across a dry branch and a delayed processor. Bypass and parameter changes do not unpredictably shift alignment. A plugin latency change triggers a prepared update with an appropriate transition. Stereo/dual-mono behavior is explicit.

**Reference:** [Apple: AUAudioUnit latency](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/latency).

### ENG-06 — Transparent gain staging and output protection · P1

**Observed:** There are per-effect sample constraints, a graph soft limiter, and final output soft protection. These nonlinear stages can color sufficiently hot signals. Several effects already smooth parameters.

**Change:** Document the full gain path. Separate non-finite/fault containment from intentional coloration and final protection. Choose a clearly specified final peak-control design, meter its gain reduction, and audit hidden nonlinear stages. Add loudness-matched A/B with documented measurement behavior. Extend parameter smoothing consistently.

**Acceptance:** Verify unity paths, gain accuracy, channel balance, overload behavior, non-finite containment, and bypass continuity. Compare spectral changes and loudness under controlled signals. Do not describe sample-peak protection as true-peak limiting unless that behavior is implemented and tested.

### REC-01 — Final-output recording and visible integrity · P0

**Observed:** Recording is called from graph processing before final output makeup/protection. Pool exhaustion or insufficient frame capacity drops recording blocks without an explicit recording-integrity warning.

**Change:** Define recording taps: final processed digital mix by default; optional raw input later. Record after the documented master gain/protection stage. Note that this is not a recording of the physical speaker or OS hardware volume. Add elapsed time, dropped-frame metrics, finalization state, and Reveal in Finder. Ensure buffer capacity accommodates variable blocks.

**Acceptance:** Saved digital samples match the documented recording tap. Writer overload is visible and never stalls live playback. Format changes have an explicit stop/split/conversion policy. Stop drains accepted writes and reports completion accurately. Disk failure produces a clear error and recoverable partial-file behavior.

**Evidence:** `Sonexis/AudioEngine/AudioEngine.swift: recordIfNeeded`, `IO.swift`, `ProcessTapBackend.swift`.

### PLUG-01 — Plugin health and recovery · P1

**Observed:** AU hosting includes asynchronous creation, editor fallbacks, and dry fallback for render failures. Failures are not consistently represented as actionable node states.

**Change:** Model discovering, loading, ready, unsupported, unavailable, and failed states. Provide retry/remove/bypass actions and preserve missing-plugin identity and saved state. Audit channel-layout fallback and failure restoration. Investigate isolation options separately by plugin type; do not assume all installed AUs have identical process isolation.

**Acceptance:** Missing plugins and failed renders remain understandable. A bad plugin cannot leave an unexplained Loading state. Mono/stereo failure paths restore valid dry buffers. Saved state survives a temporarily absent plugin. Every chain owns independent stateful plugin instances unless deliberate bus sharing is implemented.

## 6. Preset and workspace integrity

### DATA-01 — Transactional saves and corruption recovery · P0

**Observed:** Atomic writes already exist. Persistence failure sets an error after in-memory mutation; callers can still show Saved. Decode failure resets the entire collection to empty without presenting recovery, risking overwrite on a later save.

**Change:** Return explicit save success/failure, reconcile in-memory state on failure, preserve corrupt originals, maintain last-known-good backups, and version workspace/preset formats. Keep autosave separate from named presets. Make migration behavior explicit, especially for retired effects and future app assignments.

**Acceptance:** Simulated write failures never show success. A malformed preset file is preserved and recoverable. One unsupported record does not silently destroy valid records. Migrations have fixtures. Loading an older preset explains any unavailable/retired processing rather than silently promising identical sound.

**Evidence:** `Sonexis/PresetManager.swift`, `Sonexis/ContentView/ContentView.swift`.

## 7. APP-01 — Per-app chains: proposed feature design · P2

### Recommendation

Pursue per-app chains as a major product capability. Start with one selected app using the existing chain engine, then expand to independent chains for several apps. A single effect is simply a one-node chain; avoid separate “per-process effect” and “per-process chain” product systems.

Present applications in the interface, not raw process IDs. Processes are runtime capture targets. Apps are the identity users recognize and expect settings to follow across relaunches.

Examples are intended workflows, not guarantees of current compatibility:

- Spotify → warm music chain.
- Browser → dialogue clarity chain.
- Game → low-latency chain.
- Call app → leave original audio untouched.

Core Audio supports capturing a process or a group of processes. This provides an API foundation, but does not prove all app grouping, simultaneous tap, muting, and recovery behavior needed by this feature. See [Apple's capture guide](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) and [CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription).

### 7.1 MVP scope and explicit boundaries

**First experiment:** One explicitly selected running app, one chain, one current default stereo output, ordinary unselected apps playing normally. Reuse the graph editor. Demonstrate capture isolation, muting, relaunch handling, and output restoration before designing a large mixer UI.

**First product version:** A small validated number of app lanes, each with an independent chain, gain, effects bypass, and meter, feeding one shared output. Set the supported lane/complexity limit from measurements.

Defer browser-tab or website selection, per-app physical devices, microphone processing, virtual microphone delivery, cross-app sidechains, and shared mutable effects buses. Process output capture does not automatically modify the microphone signal other people hear in a call. A browser process also does not provide a stable product guarantee of one tap per tab.

### 7.2 User model

**Discussion outcome (2026-09-06):** Visual simplicity is a requirement. App selection is a setup/editing action, not something users must repeat during everyday listening. Keep one system-wide chain as the default experience; users who never customize an app should not need to encounter app routing.

Introduce optional assignments through “Customize an app.” The main view can summarize them with wording such as “System preset: Warm · 2 app overrides,” once global-with-overrides routing is supported. This is a proposed interaction model, not a promise that the current engine supports simultaneous global and per-app processing.

Show **one chain at a time** in the existing editor. Selecting Spotify displays Spotify's chain; selecting Safari displays Safari's chain. Previously configured chains continue processing in the background. Changing editor selection must not change which apps are processed, reset their DSP state, or restart their audio.

Keep the app selector collapsed or secondary until needed. When expanded, list only apps the user has customized, with an icon, name, and small state indicator. Put detailed meters, bypass controls, presets, and wiring in the selected app's workspace rather than turning every row into a mixer strip. “Customize an app” opens a picker of available apps; the permanent navigation is not a list of every running process.

Adding an app starts with “Choose a preset,” with “Build your own” as the secondary path. Most users should be able to assign a sound without constructing another graph. An offline app retains its assignment and displays “Waiting for app” when inspected.

Persist assignments and apply them automatically when the corresponding app runs again, subject to the user's processing/startup preference. Remember the last editing view. Do not switch the canvas when a different app plays sound or gains focus, and do not prompt users to reselect apps at each launch.

Example editing layout, shown only when the app selector is expanded:

```text
CUSTOMIZED APPS          SPOTIFY · Warm music
Spotify                 Input → Bass → EQ → Output
Safari
                        Effects on       Save preset
+ Customize an app
```

**Simplicity acceptance checks:**

- [ ] The default system-wide workflow needs no app selection.
- [ ] Configured assignments work across app relaunches without repeated setup.
- [ ] Only one graph is visible at a time; other configured chains continue running.
- [ ] Changing the selected editor does not change audio routing or processing state.
- [ ] Audio activity and app focus do not automatically change the editing view.
- [ ] Only customized apps appear in persistent app navigation.
- [ ] Users can assign a preset without opening the chain editor.
- [ ] Detailed routing and meters do not crowd the default listening surface.

Offer explicit routing choices:

| Choice | Meaning |
| --- | --- |
| Leave untouched | Native playback; Sonexis does not process or master-control this source |
| Process with chain | Capture source once, apply its chain, send to Sonexis output |
| Effects bypass | Keep captured lane and routing, skip chain effects; lane/master behavior remains documented |

Do not conflate effects bypass with releasing capture. Releasing capture changes latency and mute ownership and requires a controlled handoff.

Use preset copies by default: assigning a preset initializes independent settings for that app. Editing Spotify must not unexpectedly edit the browser. A later explicit linked-preset feature can offer propagation, but DSP delay lines, envelopes, and plugin instances remain independent even when settings are linked.

### 7.3 Relationship to global processing

For the first selected-app implementation, make All System Audio and Selected Apps alternative modes. This avoids silently stacking a global chain over per-app chains while capture ownership is still being proven.

This remains a technical staging proposal. The desired eventual presentation is a default system sound with optional app overrides. Before exposing that wording, resolve residual capture ownership so an override replaces the system chain for that source rather than accidentally applying both. Do not force users through a permanent mode-selection workflow merely because the first prototype uses separate modes.

Later, support a residual “Other apps” lane if needed. Its exclusion list must include every app assigned to a dedicated lane, every untouched app, and Sonexis playback processes. A source must never appear in both a dedicated lane and a residual capture mix.

An optional master chain applies only to audio routed through Sonexis. “Untouched” native audio bypasses that master, its volume, its protection, and its recording. Make this limitation visible rather than claiming a master meter covers every audible sound.

### 7.4 Proposed signal flow

```text
App A process group → capture A → aligned input → chain A → lane gain ┐
App B process group → capture B → aligned input → chain B → lane gain ├→ mixer → master protection → output
Optional Other apps → capture C → aligned input → chain C → lane gain ┘                         └→ recording

Untouched apps → normal macOS playback (outside the Sonexis mixer)
```

The independent chain processing must happen before summing. Once a tap has mixed two applications into one signal, the graph cannot independently apply one chain to each original app.

One shared output renderer is the proposed destination. Do not instantiate several whole current `AudioEngine` objects, each with its own competing default-output lifecycle. Reuse the DSP graph implementation through a smaller per-chain runtime.

### 7.5 Proposed components and persisted model

| Component | Responsibility |
| --- | --- |
| AudioProcessRegistry | Enumerate current audio processes and follow additions/removals |
| AppIdentityResolver | Map processes/helpers to a user-visible application, with confidence/fallback |
| RoutingCoordinator | Build disjoint source ownership sets and perform lifecycle transitions |
| CaptureSession | Own the selected tap, capture resources, timestamps, and bounded buffers |
| ChainRuntime | Own one compiled graph, effect state, plugin instances, and latency metadata |
| OutputMixer | Align and sum ready lanes for one output clock and protect the final mix |
| WorkspaceStore | Persist assignments, graph state, schema version, and user preferences |

Suggested persisted records:

- `AppAssignment`: stable application identity, optional display metadata, routing choice, chain ID, lane gain, effects-bypass preference.
- `ChainDefinition`: stable chain ID, versioned graph snapshot, parameter and plugin state.
- `Workspace`: mode, app assignments, optional residual lane, master settings, output preference, restoration preference.
- Runtime-only `ResolvedSourceSet`: current PIDs/Core Audio object IDs and generation token. Never persist these as application identity.

Bundle identity is a useful primary key but not a complete helper-process attribution solution. Investigate running-application metadata and process relationships; handle absent/ambiguous identities explicitly. PID reuse must not attach an old rule to an unrelated process.

### 7.6 Engineering invariants and open risks

**Exactly one playback path per controlled source.** Verify tapped-source mute semantics and teardown with actual audio. Avoid duplicate native-plus-processed playback, overlapping taps, and feedback into Sonexis. Exclude Sonexis and any hosted helper process that emits its output where applicable.

**Prepared handoffs.** Prepare graphs/resources before changing ownership. Muting, startup buffering, capture replacement, and release need an explicit state machine. Measure whether each transition duplicates, drops, or delays source audio; do not assume tap replacement is atomic. Reject or roll back transitions that leave ownership uncertain.

**Independent clocks and formats.** Current `TapCaptureEngine.prepare` requires matching Float32 tap/output formats and does not perform general sample-rate conversion. Multiple capture sources need timestamps, bounded alignment, and a common output sample-rate/channel contract. Verify what the tap/aggregate already compensates before adding another drift controller. Defer unsupported formats with a clear explanation.

**Bounded processing.** A missing or silent source cannot block output. Use bounded per-lane queues and define late-block behavior. Measure a serial shared worker before assuming one timer/thread per app is necessary. A slow plugin can still consume shared processing time; lane-level error recovery alone does not provide CPU or crash isolation.

**Latency policy.** Compensate branches inside chains. Evaluate cross-lane alignment separately: aligning every app to the slowest chain may harm interactive apps. Decide whether lanes use a common latency target, separate latency classes, or a simpler restricted MVP. Surface the consequence and validate video/game sync.

**Failure isolation.** App exit/relaunch, capture permission failure, plugin failure, and device loss each have separate recovery paths. Preserve assignments when an app exits. Fail-open native playback is a desired behavior requiring verification, not an unconditional guarantee. Verify no source remains muted after crash/forced quit.

**Tail policy.** When an app becomes silent, allow a defined reverb/delay tail before suspending processing. When the app exits or its chain is removed, apply the documented tail/transition policy without retaining capture indefinitely.

### 7.7 Delivery stages

**Stage A — Capture feasibility.** Prove selected-app capture, native mute/release, app/helper mapping, source restart, and permission errors with two independently identifiable test sources. Record supported OS/device behavior. Exit gate: source A is processed exactly once while source B remains unchanged, including stop and failure transitions.

**Stage B — Single app product flow.** Add app picker, assignment persistence, offline state, and existing chain editor integration. Keep global and selected-app modes exclusive. Exit gate: assignments survive relaunch and recover after output changes without a second engine instance.

**Stage C — Multiple independent chains.** Add chain runtimes, source alignment, shared mixer, lane meters/gain, and bounded overload handling. Exit gate: simultaneous independent tones demonstrate isolation; changing one chain cannot alter another's state.

**Stage D — Residual lane and optional master.** Introduce Other apps only after overlap/mute invariants pass. Document untouched sources and recording scope. Exit gate: membership changes do not double-process audio or create feedback.

**Stage E — Convenience and expansion.** Device profiles, macro presets, linked settings, and advanced buses only after stability/performance data supports them.

### 7.8 Feature acceptance checklist

- [ ] Select one app; verify only that source changes.
- [ ] Run two apps with distinguishable signals and different chains; verify no crosstalk.
- [ ] Relaunch an app and verify its assignment follows identity, not the old PID.
- [ ] Test supported browser/helper-process changes; document grouping limitations.
- [ ] Switch routing choices and global/selected modes without duplicate playback or stuck mute.
- [ ] Stop, quit, force-quit, and recover the app; inspect normal source playback afterward.
- [ ] Add/remove an output device and change supported sample rates while lanes are active.
- [ ] Test silent, late, overloaded, and failed-plugin lanes without starving healthy output.
- [ ] Verify recording matches the documented Sonexis mix and excludes untouched sources.
- [ ] Verify assignments, independent plugin state, and offline entries survive workspace reload.
- [ ] Measure CPU, allocations, latency, underruns, and energy with representative lane counts.

## 8. Additional feature candidates

| ID | Candidate | Priority | Dependency / intended value |
| --- | --- | --- | --- |
| FEAT-01 | Curated goal-based presets and macros | P1 | Better first result; needs reliable preset flow |
| FEAT-02 | A/B snapshots with loudness matching | P1 | Better tonal comparison; ENG-06 |
| FEAT-03 | Output-device profiles | P2 | Different speakers/headphones; ENG-02 and DATA-01 |
| FEAT-04 | Visual parametric EQ | P2 | Practical correction and clear feedback |
| FEAT-05 | Accessible dynamics/night-listening controls | P2 | Dialogue and loudness management; validate retired compressor implementation before reuse |
| FEAT-06 | Advanced per-app buses/sidechains | P3 | Requires APP-01 stability and explicit routing semantics |

Compressor and 10-band EQ types exist but are retired from the current tray. Treat restoration or replacement as deliberate product/DSP work, not a missing-code assumption. VST-related code also exists; do not advertise working VST hosting from that fact alone.

## 9. Validation plan and release gates

### Automated regression targets

- Preset write failure, partial corruption, migration, unsupported plugin/effect, and workspace restoration fixtures.
- Ring-buffer wraparound, capacity bounds, variable block sizes, underflow/overflow metrics, and gain ramps.
- Graph impulse response, parallel latency alignment, stereo/mono behavior, non-finite containment, and edit continuity.
- Recording sample comparison, bounded writer overload, format changes, finalization, and disk failure.
- Engine lifecycle state sequences with stale callbacks, retry exhaustion, and stop during recovery.
- App-assignment resolution, PID reuse, disjoint source ownership, and preset-instance independence.

### Manual and device matrix

Test the minimum supported macOS version and a current supported version. Cover built-in output, wired/USB output, and Bluetooth; 44.1/48 kHz and any additional advertised formats. Exercise unplug, default-output change, sleep/wake, app relaunch, silence-to-sound transitions, and long playback.

Audio workloads: passthrough, one built-in effect, a complex serial chain, parallel wet/dry, dual mono, supported AU plugins, recording, and simultaneous app lanes. UI workloads: resizing, all themes, keyboard-only interaction, VoiceOver, Reduce Motion, tutorial exit, and restored sessions.

Record hardware/OS, build revision, route, sample rate, graph/preset, elapsed run time, measured latency, underruns, CPU/energy, and pass/fail evidence. Establish quantitative performance budgets from baseline measurements before committing to published limits.

### Release gates

No misleading Saved/running state; no known destructive preset recovery; no unreported recording drops; documented graph-edit continuity; verified source restoration on stop/failure; no feedback or duplicate capture in per-app mode. A smoke start/stop test is useful but does not replace these gates. The inspected project has a smoke hook but no app test target covering this matrix.

## 10. Recommended sequence and decisions

**Phase 1 — Trust:** DATA-01, UX-01, ENG-02/UX-03, REC-01. Add targeted tests while addressing each issue.

**Phase 2 — Everyday use and continuity:** ENG-01, UX-02, UX-04/05/06/08. Begin latency/allocation baselines for ENG-03/04.

**Phase 3 — Audio architecture:** ENG-03/04/05/06 and PLUG-01. Per-app work remains deferred while we address the current app's agreed fixes.

**Phase 4 — Per-app product:** Revisit the simplicity requirements and start with APP-01 Stage A, then Stages B/C and residual/master behavior only if validated. Reassess remaining feature candidates using actual usage and performance data.

### Working agreement from the discussion

Fix the current experience before moving to per-app chains. Discuss roadmap items one at a time, settle the intended behavior and scope, then implement and validate the selected item before moving on. This document update does not start feature implementation or approve every proposed backlog detail.

For each item: explain the current issue and user impact; agree on the concrete change; implement within that scope; run its acceptance checks; record the result and remaining limitations. Avoid bundling unrelated visual or engine changes into that item. DATA-01 is the recommended first discussion because it concerns saved work; the exact item order remains adjustable.

Decisions requiring product/engineering review:

- Whether the default launch surface is compact listening or the restored editor.
- Closing the window keeps processing; Dock reopens it and explicit Quit exits (resolved 2026-09-08).
- Exact preset-copy versus linked-preset semantics; recommendation: copies first.
- Whether global mode and selected-app mode remain exclusive after MVP.
- App grouping confidence/fallback rules and supported browser behavior.
- Cross-app latency policy and supported format/output scope.
- Recording format-change policy and which recording taps to expose.
- Quantitative latency, overload, and maximum-complexity budgets after measurement.

These unresolved details remain proposals. The agreed direction is current-app fixes first, one-at-a-time discussion and execution, and optional per-app customization that does not add recurring app-selection work.

## 11. Working log

Use one row per active item; extend as work begins.

| Item | Owner | Status | Issue/PR | Validation evidence | Next action |
| --- | --- | --- | --- | --- | --- |
| DATA-01 | Codex | Save-reliability scope implemented | Working tree | Persistence regression checks and Debug build passed | Manual UI check; broader migration work remains separate |
| UX-01 | Codex | Load-library management implemented | Working tree | Debug build and persistence action tests passed | Manual file-picker and UI verification; recoverable loading remains separate |
| UX-01 identity | Codex | Implemented | Working tree | Saved-content comparison checks and Debug build passed | Manual header/plugin editor verification |
| ENG-02 | Unassigned | Deferred by user | — | Recovery-path inspection | Revisit after current fixes |
| REC-01 | Codex | Recording correctness implemented; live verification pending | Working tree | WAV writer regression checks and Debug build passed | Live makeup/protection comparison and device-change check |
| ENG-01 | Codex | Forced dropout and shared-state double render fixed | Working tree | Transition waveform checks and offline engine/recording integration passed | Live listening; tail preservation and latency alignment remain separate |
| UX-02 | Codex | Workspace recovery implemented | Working tree | Persistence/recovery regression tests and Debug build passed | Manual quit/relaunch, tutorial and native plugin-editor checks; first-launch redesign remains separate |
| UX-08 | Codex | Background operation and Dock reopening implemented | Working tree | Window-controller tests and Debug build passed | Live close/reopen/quit audio check |
| ENG-04 | Codex | Routing-plan preparation and reuse implemented | Working tree | Legacy/new sample comparison, cache tests, engine integration and Debug timing | Live complex-chain check; profile/reuse temporary audio buffers next |
| APP-01 A | Unassigned | Deferred | — | API feasibility only | Revisit after agreed current-app fixes |

Completion note template: item ID; implementation summary; changed behavior; tests/measurements; remaining limitations; revision/PR; reviewer; completion date.

### DATA-01 implementation note — 2026-09-06

Authorized scope: save reliability, preserving the current Save/Load workflow. Preset mutations now commit to published memory only after successful atomic persistence. Save and Save As show success and advance the tutorial only on success. Failed Save As retains the dialog/name and shows an inline error. Overwrite imports retain pending input on failure. Deletion/import use the same transactional persistence path.

A `presets.backup.json` copy preserves the prior committed library before replacement (the first save seeds a recovery copy). Unreadable primary bytes are archived to a unique `presets-unreadable-<UUID>.json` before backup recovery. Recovery is disclosed and may omit the most recent changes. If preservation fails, storage cannot be read, or no valid backup exists, writes are blocked to protect recoverable data. Repair/restore storage and reopen the app to retry blocked initialization; no silent temporary-storage fallback is used.

Validation: `sh Scripts/test-preset-persistence.sh` compiles the real persistence code and preset/graph models and tests save/reload, failed creation/update/deletion/import, unchanged memory/disk on failure, backup-write failure, successful retry, missing IDs, exact corruption archival, backup recovery, blocked unsafe writes, and missing-primary recovery. Debug macOS `xcodebuild` passed with signing disabled. `git diff --check` passed. Tests use temporary directories and do not modify the user's preset library.

Remaining limits: interactive UI behavior has not been manually exercised; recovery currently uses the entire valid backup rather than salvaging individual records from malformed JSON. New schema/version migrations, autosave, preset-library navigation, and workflow redesign are outside this fix. Changes are in the working tree, not committed or released.

### UX-01 preset identity implementation note — 2026-09-06

Authorized follow-up: display the active preset name, “Untitled chain” for an unnamed chain, and “Modified” after changes. The name/status now appears above the existing Save/Load controls to preserve toolbar width. Long names truncate with a full-name tooltip. Existing Save and Save As behavior is retained.

The indicator compares current saved graph content against the persisted preset, including parameters, enabled state, nodes, effective automatic order, wiring, gains, and available plugin state. Layout-only movement and tile accent changes do not mark the preset modified; moving nodes in Automatic mode does when it changes the effective chain order. Positions are still saved when the user chooses Save. Undo to matching content clears it; failed saves leave it modified. Comparison normalizes generated wire IDs and edge ordering, excludes migration bookkeeping and unused terminal IDs, and does not include engine power, theme, meters, or editor selection. Untitled chains display their label without a saved-preset comparison.

Plugin state is refreshed on the existing two-second timer and immediately before saving, without rebuilding audio; the canvas preserves previously saved plugin state while an instance has no state available. Native plugin editor changes can therefore take up to the polling interval to appear and depend on the plugin exposing its state. No plugin-specific live editor validation was performed.

Validation: the persistence regression script also covers clean reload, parameter/bypass/node/routing/gain changes, layout-only movement remaining clean, automatic reordering, undo-equivalent restoration, transient connection identity/order, failed-save dirty state, and successful-save clean state. Debug macOS build with signing disabled and diff whitespace checks passed. Interactive visual QA remains pending. Unified preset-library navigation and autosave remain separate roadmap work.

## 12. Evidence index

Paths are relative to the repository root. Prefer symbols over fixed line numbers as the code changes.

- `Sonexis/SonexisApp.swift`: window-close termination and smoke entry point.
- `Sonexis/ContentView/ContentView.swift`: screen routing, save feedback, transient workspace state.
- `Sonexis/ContentView/HomeView.swift`: first/return launch entry experience.
- `Sonexis/ContentView/HeaderView.swift`: power, bypass, recording, meter, warnings.
- `Sonexis/ContentView/PresetView.swift`, `LoadPresetDialog.swift`: library versus load surface.
- `Sonexis/ContentView/TutorialController.swift`: tutorial progression and locking.
- `Sonexis/CanvasView/CanvasView.swift`: graph editing, manual-mode clearing, undo/redo, toolbar.
- `Sonexis/CanvasView/EffectBlockHorizontal.swift`, `EffectParametersViewCompact.swift`: tiles, labels, knobs, numeric entry.
- `Sonexis/PresetManager.swift`: `persistPresets`, `loadPresets`, mutation/save behavior.
- `Sonexis/AudioEngine/IO.swift`: `applyGraphChangeCrossfade`, `interleavedData`, capacity helpers.
- `Sonexis/AudioEngine/Graph.swift`: `processGraph`, `mergeInputs`.
- `Sonexis/AudioEngine/Effects.swift`: smoothing, soft limiter, per-effect output sanitization.
- `Sonexis/AudioEngine/AudioEngine.swift`: snapshots, locks, `recordIfNeeded`, recording pool.
- `Sonexis/AudioEngine/PluginHosting.swift`: plugin interface, rendering, configuration, failure fallback.
- `Sonexis/AudioEngine/ProcessTapBackend.swift`: output gain/protection, lifecycle bridge.
- `Sonexis/ProcessTapEngine/ProcessTapDSPApp.swift`: reservoir target, device lifecycle, retries.
- `Sonexis/ProcessTapEngine/ProcessTapProcessingWorker.swift`: periodic worker and chunk processing.
- `Sonexis/ProcessTapEngine/TapCaptureEngine.swift`: current global exclusion tap, self-exclusion validation, format restriction.
- `Sonexis/ProcessTapEngine/RealtimeAudioRing.c`: bounded buffering and fill correction.
- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
- [Apple: CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription).
- [Apple: AUAudioUnit latency](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/latency).

### Preset label refinement — 2026-09-06

User decision: new chains show no preset-name row or placeholder. The header shows a name only after successful Save/Save As or Load. “Modified” remains limited to an existing preset whose processing content has changed. This supersedes the earlier “Untitled chain” proposal and implementation note. The absent label has no visible placeholder; its space is reserved to keep toolbar and canvas geometry stable. Save/Load remain available.

### Preset typography refinement — 2026-09-06

Keep the preset name above Save/Load, as requested. Use 13-point semibold text and a small amber dot for unsaved changes, with no rounded background or vertical divider. The full name and unsaved status remain available through the tooltip and accessibility label/value. New chains still show no preset-name row.

### Stable preset toolbar geometry — 2026-09-06

Reserve fixed-width, fixed-height slots for the preset name and save-status message even when their text is absent. Reserve the modified dot's space as well. Loading a preset, toggling modified state, and showing/clearing save feedback must not change toolbar height or available canvas size. Empty labels are hidden from accessibility. This supersedes the earlier removal of layout space for unnamed chains.

### Compact side placement — 2026-09-06

User accepted moving preset identity beside Save/Load to reduce toolbar height and requested restoring the explicit “Modified” text. Use a fixed 130 × 32-point identity block with semibold name and a compact secondary line: Modified for unsaved edits, otherwise transient save feedback. A thin divider separates the block from Save/Load. The name and status share one toolbar row with the buttons; no extra feedback row expands the toolbar. Empty states keep the same geometry, with no visible placeholder. This supersedes the above-buttons and dot-only styling decisions.

### Save As dropdown alignment and styling — 2026-09-06

Replaced the native macOS Save As menu with an overlay anchored to the left edge of the entire Save split button, six points below it. The dropdown uses the existing Sonexis floating-panel surface, border, shadow, rounded typography, and themed hover state. It does not participate in toolbar layout. The header layers above the canvas so the menu remains visible. The arrow toggles dismissal; outside clicks and Escape dismiss; Return/Space activate Save As. Event monitors are removed when the menu disappears. Debug macOS build and diff whitespace checks passed; interactive visual/input verification remains pending.

### Save dropdown screenshot corrections — 2026-09-06

The dropdown now derives its width from the full Save split button rather than using a 140-point fixed width. Its left and right edges align with that button. Apply header z-order at the ContentView sibling level and use an opaque menu surface so the toolbar divider and canvas do not draw through it. The menu remains an overlay and does not resize the toolbar.

### Header-owned separator correction — 2026-09-06

Follow-up found the header's own bottom separator was a foreground overlay, so raising the header above canvas siblings did not remove the line across its dropdown. Move that separator to a background layer behind header contents. This addresses the separate ancestor-overlay issue missed by the preceding z-order change.

### UX-01 Load-library management — 2026-09-06

The existing Load window is now the normal library entry point for search/apply, Import, Rename, Export, and Delete. An ellipsis beside each preset reveals a themed inline actions strip within that row. Only one strip is expanded at a time; the main row still loads the preset, while action buttons do not apply it. No additional toolbar button or navigation screen was added. Empty-library and no-search-match states are distinct, with Import and Clear search available as appropriate. Management controls are disabled during tutorials.

Import/export reuse the existing versioned `.sonexis`/JSON codec and native file pickers. Duplicate-name imports offer Replace, Keep Both with an automatically unique name, or Cancel. Replacement preserves the existing library ID so an active preset stays identifiable. Rename uses the existing themed form, validates nonempty/unique names, and preserves ID, creation date, and saved graph. All mutations use transactional persistence; errors remain visible in the Load window or rename form. Delete asks for confirmation and does not clear the current canvas. Export writes the saved preset, not unsaved canvas edits.

Validation: Debug macOS build passed. Persistence regression checks cover rename validation, case-insensitive duplicates, write failure, ID/date/graph preservation and reload; replacement identity, duplicate import IDs, and deletion/reload, in addition to prior save and modified-state tests. Diff whitespace checks passed. Interactive dialog, native file-picker, keyboard, and visual checks remain pending. The old standalone PresetView remains in source but is not a newly exposed navigation destination. Preserving an unsaved workspace when loading a different preset remains separate work.

### Preset identity and right-click actions — 2026-09-06

Replace the Load window ellipsis/expanding action strip with right-click context actions for Rename, Export, and Delete. Left-click continues to load; Delete retains confirmation. The hover help explains right-click actions. Native contextual menus are used for these standard right-click commands; the explicitly styled Save dropdown remains custom.

Give the active toolbar name a small PRESET label, with Modified alongside that label and the semibold name below. Keep the existing fixed 130 × 32-point identity area and divider beside Save/Load, with no filled container or rounded badge. Saved feedback remains available in the tooltip; unnamed save feedback can use the name slot. No visible preset placeholder is introduced. Debug build and diff checks passed; visual review remains pending.

### Preset label spacing and fade — 2026-09-07

Place Modified directly beside PRESET with six-point spacing instead of pushing it to the far edge. Fade the identity block in/crossfade it over 220 ms when the displayed preset name changes, including first save/load. The fixed 130 × 32-point outer slot remains unchanged so the transition does not resize the toolbar or canvas.

### Stable resizing pass — 2026-09-07

User-approved direction: retain one layout; do not scale text, wrap button labels vertically, or automatically rearrange controls as the window narrows. Set the content minimum to 1,100 × 700 points and reserve at least 820 points for the canvas pane alongside the 252-point expanded effects tray. Canvas toolbar spacing is reduced from 18 to 10 points. Menu labels keep their intrinsic single-line dimensions; Save/Load and shared dialog actions have protected dimensions and single-line text. The main header supplies single-line labels by default (diagnostic messages retain their explicit two-line limit).

Remove text-shrinking modifiers from effect tiles, parameter labels/units, effects-tray rows/tabs, and Save As. Long names truncate at a consistent font size. Existing explicit canvas zoom remains separate; no new automatic zoom or routing changes are introduced. Additional window area remains available to the canvas.

Validation: Debug macOS build and diff whitespace checks passed; source inspection confirms no remaining minimumScaleFactor modifiers in app Swift files. Live visual resizing at minimum/medium/large widths, long plugin names, expanded controls, and simultaneous diagnostic messages still needs manual verification. The minimum size is a deliberate initial layout constraint and can be tuned following that review.

### Modified beside the preset name — 2026-09-07

Move the amber “· Modified” text from the PRESET caption line to the actual name line, aligned on the text baseline. PRESET stays above both. Keep the 130 × 32-point slot, fade transition, and single-line truncation; the status stays readable while long names truncate. This supersedes the prior caption/status arrangement.

### Current priorities and REC-01 recording correctness — 2026-09-07

The user confirmed the Save/Load/status workflow works correctly and considers that scope complete. Broader preset migrations remain separate. Engine lifecycle/recovery (ENG-02/UX-03) is deferred by user choice. Recording correctness is the next authorized fix; graph-edit continuity (ENG-01) remains separate.

Recording now copies the final digital output from one location after output makeup and protection, including processing bypass and fallback paths. Earlier graph-level recording hooks are removed. This tap captures Sonexis DSP output before playback buffering/device handling; it does not capture physical speaker output, OS volume, or downstream playback underruns.

Each recording owns a bounded, preallocated buffer pool and serial disk writer. Variable blocks fit within the prepared capacity (at least the worker's 1,024-frame chunk size). Pool exhaustion and oversized blocks count missing frames and show a warning on the recording control. These blocks are omitted, so the file is shorter; silence is not inserted to preserve wall-clock timing. Disk writes stay off the audio worker. Stop shows “Finishing…” and prevents a new recording until all accepted writes finish and the file closes. Application termination also drains queued writes.

Sample-rate or channel-count changes stop recording with an explanation, preserving already accepted blocks in the original format. There is no implicit conversion or split file. Disk errors stop recording and identify the saved file as potentially incomplete. An incomplete-recording alert offers Show File; overload completion reports the missing frame count.

Validation: `sh Scripts/test-recording.sh` passed using the actual writer and temporary WAV files. Coverage includes exact stereo sample values/order, variable blocks, stop/drain ordering, post-stop rejection, bounded writer overload, oversized-block recovery, format changes preserving queued audio, injected disk failure, and an independent mono session. Debug macOS build and diff whitespace checks passed. Source inspection verifies the single final-output tap covers all positive-length output paths. Live playback/WAV comparison with makeup and protection, device switching, and visual alert verification remain manual checks; no physical-output listening test is claimed.

Remaining REC-01 polish: elapsed-time display and convenient Reveal in Finder for successful recordings. These are separate from the recording-correctness fix and should not expand the existing toolbar without a design review.

### ENG-01 graph-edit dropout fix — 2026-09-07

Remove the graph-change path that inserted 20 ms of zeros followed by a 120 ms fade-in. Replace it with a worker-owned, five-millisecond smoothstep ramp from each channel's last emitted sample into the newly rendered output. The weights sum to one, so the ramp stays between its anchor and the current new sample instead of boosting correlated signals. There is no additional buffering delay. This is a short boundary-smoothing ramp, not a full old/new graph crossfade; it can briefly change the waveform near an edit.

Automatic, manual, split, global bypass, and reconfiguration output share this transition stage before final makeup/protection and recording. The identity includes routing mode and auto-connect flags, in addition to the existing topology/enabled-state signature. Rapid edits restart from the actual last emitted sample. Sample-rate/channel changes discard incompatible history; starting a new engine session resets history before its worker starts. Unchanged audio passes through without modification.

Remove the separate 200 ms automatic/manual transition that rendered both graphs against shared effect instances and summed them with equal-power weights. Only the selected graph renders now. Existing per-node DSP state remains under its existing ownership/reset rules; this transition does not create a second stateful render or reset unchanged effects itself.

Validation: Debug macOS build passed. `sh Scripts/test-graph-transitions.sh` checks unchanged samples, same-signal edits without dips/boosts at 44.1/48/96 kHz, bounded polarity changes, arbitrary block partitions, rapid edits, mode/bypass changes, format/reset isolation, and sustained-tone output without an inserted silent run. `sh Scripts/test-graph-transition-integration.sh` links the current Debug app and exercises real offline DSP through add/remove/reorder/rewire, global bypass, split/manual/automatic routing, and recording. Neutral audio remains continuous, saved WAV samples exactly match final emitted samples, and a shared tremolo advances exactly once per block in both directions of an automatic/manual switch. Tests use temporary files and never start live capture/playback.

Remaining limits: no claim of a completed live music/plugin listening test. Removing delay/reverb still follows existing tail disposal behavior; this fix does not preserve those tails or align differing plugin latencies. Preparation of compiled graphs outside the worker, independent old/new effect state for longer crossfades, and asynchronous plugin-readiness transitions remain follow-up engine work. The short ramp bounds its own blend; it does not normalize a deliberately louder new chain or prevent all possible plugin-generated transients.

### UX-02 automatic workspace recovery — 2026-09-07

Authorized scope: restore the last working canvas on relaunch, including unsaved changes, independently of named presets. First-launch redesign remains separate. Following the user's launch-screen preference, a recovered session starts on Home with its workspace queued; entering Build restores that canvas and preset identity. Automatic tutorial startup is skipped for recovered sessions. Capture and recording remain stopped; their running states are not serialized.

The versioned `workspace.json` in Application Support/Sonexis contains the full graph snapshot (node IDs, positions, parameters, enabled states, plugin state, wiring, split lanes, and gain overrides), active preset ID, effects-bypass preference, input trim, output makeup, and output protection. Preset identity resolves against the existing library. Modified is recomputed with the existing saved-content comparison; the preset itself is never overwritten by autosave. If that preset is missing, the recovered graph remains available without a preset name. Empty and never-named workspaces are valid recovery states.

Canvas edits publish their snapshot before the existing audio-apply debounce. Workspace writes are debounced by 500 ms, encoded and atomically written on a serial storage queue, and skipped when unchanged. Normal window closure and application termination capture/flush the latest pending workspace. Native plugin state refreshes through the existing two-second timer and at shutdown. Abrupt termination can still lose edits inside the debounce interval or plugin changes since the last refresh; this is recovery storage, not a guarantee against every crash or disk failure.

Each successful update keeps the previous valid workspace as `workspace.backup.json`. Unreadable primary data is copied into Workspace Recovery before restoring a valid backup. Unsupported versions and unrecoverable files pause autosave and offer Retry Restore, Show Recovery Files, and Start Fresh. Start Fresh archives both originals before clearing them; preservation failure leaves autosave blocked. Incomplete graph objects and duplicate identifiers are rejected rather than silently becoming empty canvases. Recovery never writes the named preset library.

Active tutorials suspend workspace capture and flush the pending user workspace before demo edits begin. Skipping restores the prior canvas; a first-launch tutorial also has an explicit empty prior canvas. Existing tutorial completion behavior remains: if a lesson intentionally keeps its result, that result becomes the working canvas after the tutorial ends.

Validation: `sh Scripts/test-workspace-persistence.sh` passed with temporary directories and the actual models/store. Coverage includes graph/layout/settings/identity round-trip, Modified comparison, preset-file isolation, unchanged-write suppression, debounce and immediate-quit flushing, corrupted-primary backup recovery and archival, future-version preservation, explicit fresh start, incomplete/duplicate graphs, injected disk failure and retry, anonymous/empty workspaces, split/plugin-state data, and archival failure. Debug macOS build passed. Live quit/relaunch UI checks, native plugin editor restoration, and tutorial flow verification remain manual checks. Undo history, selection, viewport zoom/pan, and first-launch design are outside this change.

### Empty Manual canvas audio — 2026-09-07

An empty Manual canvas (or empty split lane) passes input through without creating a visible Start → End wire. Automatic → Manual converts only populated chains; empty lanes receive no generated manual connections. The engine passthrough applies only when both nodes and connections are empty. Once an effect is present, manual wiring determines the output, so disconnected effects do not create an implicit dry path. Explicit Start → End wires still honor their gain. Existing graph limiting and final output protection remain in the signal path. Clearing the canvas returns to audible passthrough.

Validation covers empty manual passthrough, disconnected effects producing no routed output, explicit dry-wire gain, and empty split lanes through the offline engine integration test. Live visual confirmation remains a manual check.

### Disconnected effect styling trial — 2026-09-07

User explicitly prefers no added labels or hover text for disconnected effects. Trial a subtle amber outline/glow on tiles outside the current signal path, retaining the existing dimming and separate selection outline. The overlay does not receive pointer events or change layout. This supersedes the proposed disconnected-state text/hint for this pass. Visual feedback from the user will determine whether to keep or tune the glow.

### Wire animation after menu dismissal — 2026-09-07

Remove the canvas's application-wide window key/resign subscriptions. Popup-window focus events could mark the canvas inactive even though its own window stayed focused; choosing the already-selected Stereo option does not emit a graph-mode change, so the existing mode-change refresh did not repair this. Retain the window-scoped WindowFocusReader as the focus source. Signal-flow refreshes now use that canvas focus state instead of the application's currently key popup/plugin window. Graph routing and mode selection are unchanged. Debug build/whitespace verification passed; manual repro is selecting Stereo again while already in Stereo with Manual wiring and audio running, then checking arrows continue after menu dismissal.

### Background editor lifecycle — 2026-09-08

The app now has a single SwiftUI editor Window. A retained window controller intercepts ordinary close requests and orders the editor out instead of destroying its content and StateObjects. The existing SwiftUI window delegate receives all other callbacks through forwarding. Dock reopening brings that same window forward, deminiaturizing when necessary, even if a plugin window is visible. Explicit termination enables the normal close path and retains the existing engine shutdown/recording drain. Hiding refreshes plugin state and flushes workspace storage; it does not stop the engine or add a menu-bar item.

Validation: Debug build and `sh Scripts/test-background-window.sh` passed. Tests use non-presenting AppKit test windows and verify hide versus quit, content/window identity across repeated reopening, workspace-hide notifications, minimized reopening, delegate forwarding, and repeated attachment/detachment. No live capture or real user workspace was used by these tests. Live red-close/Command-W, Dock-click, and Command-Q playback verification remains a manual check. This supersedes the earlier menu-bar and optional-close-preference proposal.

### ENG-04 routing-plan implementation and measurements — 2026-09-08

`GraphRoutingPlan` prepares reachability, incoming edges, automatic sink connections, and effect execution order before the processing snapshot is published. Plans store routing and effect IDs/types, not mutable DSP state or captured parameter values. One cache per manual/left/right graph compares routing-relevant fields, so parameter updates and edits to the other split lane do not recompile an unchanged plan. Existing snapshots retain their immutable plan while an updated snapshot is published under the existing snapshot lock. The worker no longer rebuilds adjacency maps, walks reachability, searches nodes, or runs a topological queue every block.

The render path still uses current snapshot parameters/enabled state and the same per-node effect instances. Merge order for explicit edges, gain handling, implicit-end policy, disconnected/cyclic graph behavior, empty-canvas passthrough, and missing-endpoint passthrough are preserved. Automatic serial chains without graph routing already iterate a prepared node order and remain unchanged. Output dictionaries, merge-buffer allocations and DSP scratch allocation still exist; this is not a claim of allocation-free or lock-free processing. Retired-plan reclamation and real-time allocation profiling remain follow-up work.

Validation: Debug build passed. `sh Scripts/test-compiled-graph.sh` compares 43,710 mono/stereo samples with a frozen test-only copy of the pre-change renderer at block sizes 1/17/128/1,024/31/256, including EQ/tremolo/delay state, serial and parallel routing, implicit sinks, explicit dry gains, duplicate edges, unreachable predecessors and cycles (tolerance 1e-6 for floating-point summation). It also checks missing endpoints, cache reuse/invalidation, fresh parameters/bypass and independent split plans. `sh Scripts/test-graph-transition-integration.sh` passed, covering graph edits, bypass, split/manual/automatic modes, empty/manual lane behavior, exact final-output WAV recording and single advancement of shared DSP state.

Same-process Debug timing, neutral EQ chains, 128 stereo frames per block, median of five 200-block runs after warmup:

| Nodes | Previous renderer | Prepared routing | Reduction |
| --- | --- | --- | --- |
| 4 | 151.14 microseconds/block | 133.92 microseconds/block | 11.4% |
| 16 | 514.28 microseconds/block | 456.63 microseconds/block | 11.2% |
| 48 | 1,546.53 microseconds/block | 1,316.50 microseconds/block | 14.9% |

These timings isolate the offline renderer in a Debug build, not total app CPU, optimized Release performance, hardware latency, or worst-case scheduling. The standalone pre-change baseline was also recorded (149.45/518.10/1,554.73 microseconds for 4/16/48 nodes). Live complex-chain/plugin listening and load testing remain manual checks. The 4,096-frame playback buffer remains unchanged, following the user's latency decision.


### Automatic routing after switching modes

Fixed a pre-existing bug where Automatic → Manual → Automatic retained manual edges that overrode position-based routing, leaving newly added effects disconnected. Automatic now derives its chain solely from node positions in each lane; retained manual edges cannot override it, including in restored snapshots. Automatic → Manual still materializes the generated wires with their gains. Preset comparison follows the same rule and ignores inactive manual edges in Automatic mode. Regression coverage checks retained edges, inserted nodes, and reordered nodes; User verified the mode-switch fix in the live app and confirmed audio sounds good.
