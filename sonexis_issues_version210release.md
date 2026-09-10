# Sonexis 2.1.0 — confirmed release issues

Audit date: 2026-09-10. Status: findings only; fixes have not been implemented.

Tested the working tree based on `451f5baf66dce0bbfb6c87b35e154fdef92a5359`, including the subsequent uncommitted app changes. The tested app still reports **2.0.1 (3)**; this report concerns its planned 2.1.0 release. Machine: Apple M4, 16 GiB RAM, 10 logical CPUs, macOS 26.5.2 (25F84), Xcode 26.6.

Every entry below has observed failure evidence. The underlying cause of the Core Audio stall is explicitly unresolved. Passing checks, synthetic stress limits, and tests that could not be completed are recorded in the [audit record](docs/RELEASE-2.1.0-AUDIT.md), not presented as additional defects.

## Priorities

| ID | Priority | Confirmed problem | Evidence type |
| --- | --- | --- | --- |
| 210-01 | P1 | Imported Bitcrusher parameters can crash the audio processor | Repeated Debug and optimized Release reproduction |
| 210-02 | P1 | A stalled audio-device start freezes the entire app UI | Actual app timeout and two main-thread samples |
| 210-03 | P1 | Turning on pitch shifting interrupts continuous audio for about half a second | Deterministic engine output, two sample rates, saved WAV |
| 210-04 | P2 | Narrowing the window clips preset nodes outside the canvas | Actual before/after screenshots and repeat |
| 210-05 | P2 | Input and Output Gain sliders have no accessible names | Actual accessibility tree plus control source |
| 210-06 | P2 | App Chains tutorial can leave processing off with no way to turn it on | Actual tutorial states plus both power-control guards |

P1: resolve before public release. P2: polish the existing workflow before release, or explicitly accept a documented limitation. These are prioritization recommendations, not claims that every test environment or graph reproduces every issue.

## 210-01 — Imported Bitcrusher values crash on the first processed block

**Impact:** A user can import a syntactically valid preset which later terminates the processing process. This is a local preset-triggered denial of service; no remote execution or data disclosure was demonstrated.

**Reproduction:** From the repository root, prepare the [audit tools](Tests/ReleaseAudit/README.md), then run either command in its own process:

```sh
.build/ReleaseAudit/audit malformed bitcrusherBitDepth
.build/ReleaseAudit/audit malformed bitcrusherDownsample
```

Each probe calls the real `decodePresetImportData`, calls `validateForIndependentProcessing`, applies the decoded graph, and processes one 1,024-frame stereo block. The fixtures contain the finite JSON number `1e100` in the named parameter; they do not require NaN, invalid JSON, a plugin, or actual audio capture.

**Expected:** Reject the parameter or constrain it to its supported range before DSP.

**Actual:** Import and graph validation both accept it. Both Release cases terminate with signal 5 (`SIGTRAP`). Debug repeats fail with: `Double value cannot be converted to Int because the result would be greater than Int.max`.

**Evidence:** [Release results](docs/release-2.1.0-evidence/audit-results.json), [bit-depth Debug error](docs/release-2.1.0-evidence/debug-malformed-bitcrusherBitDepth.log), [downsample Debug error](docs/release-2.1.0-evidence/debug-malformed-bitcrusherDownsample.log), and the [small JSON fixture](Tests/ReleaseAudit/malformed-bitcrusherBitDepth.json).

**Location:** `Sonexis/AudioEngine/Effects.swift`, Bitcrusher branch, converts both decoded Doubles to Int before bounding them. `GraphSnapshot.validateForIndependentProcessing` currently checks duplicate node IDs and split endpoints, not these numeric ranges. `decodePresetImportData` returns the decoded graph without numeric validation.

**Required work:** Validate the imported/persisted parameter values and bound before integer conversion at the DSP boundary. Check both fields and retain the two crash fixtures as regression coverage. Do not just catch JSON decoding errors; this JSON decodes successfully.

**Limit:** The reproduction deliberately bypasses the UI knob's normal range. It does not establish that ordinary knob dragging generates these values. The malicious fixture was never imported into the user's real library.

## 210-02 — Audio startup can block the main UI thread indefinitely

**Impact:** The editor cannot respond to input or cancel the start while a Core Audio call is stalled. This was observed in the normal Debug app, not just an offline test harness.

**Observed sequence:** After the live-audio stress probes, start the App Chains lesson with processing stopped; create the Terminal practice chain; use Right-arrow navigation through the menu-bar instructions; remove the practice tab and confirm; choose **Continue** on the completion card. Continuing enters Advanced Wiring, which starts the engine.

**Expected:** Starting audio must leave the app responsive, with a recoverable start/failure state.

**Actual:** The UI request timed out and a second inspection also timed out. Samples taken at **02:11:03** and **02:12:05** both show the main thread blocked inside Core Audio `AudioDeviceStart`. The stack runs through:

```text
ContentView.ensureTutorialEngineRunningIfPossible
→ AudioEngine.start
→ ChainWorkspace.togglePower
→ MultiChainAudioEngine.start / startPipelines
→ ProcessTapDSPEngine.start
→ ProcessTapDSPApp.startIO
→ TapCaptureEngine.start
→ AudioDeviceStart
```

The frozen audit instance had to be terminated and relaunched. Its saved JSON files remained byte-identical to the pre-test copies.

**Evidence:** [first actual-app sample](docs/release-2.1.0-evidence/app-continuation-hang.sample.txt), [second sample](docs/release-2.1.0-evidence/app-continuation-hang-second.sample.txt), [action record](docs/release-2.1.0-evidence/ui-app-continuation-timeouts.txt), and [saved-data comparison](docs/release-2.1.0-evidence/data-after-tutorials.json).

**Required work:** Isolate potentially blocking HAL lifecycle calls from the main UI thread and define how a pending start can fail/recover without freezing the editor. Preserve single ownership and correct teardown when doing so; merely dispatching every lifecycle call independently is not sufficient. Re-test ordinary Power as well as tutorial-triggered startup under the reproduced stalled-service condition.

**Important limit:** Earlier tutorial starts succeeded on this Mac. The normal-app freeze was observed after standalone probes stalled in HAL create/start/stop calls. The audit does **not** establish why the HAL service stalled or that a fresh launch on a fresh audio-service session will trigger the stall. The confirmed Sonexis defect is that the stalled call also blocks the whole UI for over a minute; this is not evidence that the tutorial itself caused the underlying HAL failure.

## 210-03 — Changing Pitch from zero to +7 semitones creates a long silent gap

**Reproduction:** Run:

```sh
.build/ReleaseAudit/audit pitch-edit
```

The probe feeds a continuous stereo signal through one Pitch (Rubber Band) node at zero semitones for 40 blocks. It then changes that same node to +7 semitones using the real graph update path, preserving its identity, and continues processing. Input/Output Gain are -15/+15 dB. No device, tap, plugin, or source restart is involved.

**Expected:** Preserve audible continuity while the pitch processor prepares its output, then transition to the shifted signal.

**Actual:** Both output channels become silent immediately after the parameter change:

| Sample rate | Consecutive silent frames | Duration |
| --- | ---: | ---: |
| 44,100 Hz | 24,237 | 549.59 ms |
| 48,000 Hz | 24,236 | 504.92 ms |

**Evidence:** [measurements](docs/release-2.1.0-evidence/pitch-edit.log), [actual processed WAV](docs/release-2.1.0-evidence/pitch-edit-output.wav), [fresh pitch continuity comparison](docs/release-2.1.0-evidence/pitch-gaps.log), and [reproducer](Tests/ReleaseAudit/main.swift). The WAV changes pitch after frame 40,960; it contains generated test audio only.

**Location:** `Effects.swift` bypasses the pitch processor at effectively zero semitones, then substitutes its output immediately when activated. `RubberBandWrapper.mm` uses an 8,192-frame minimum process batch and waits for two batches of output to prime; while unprimed it fills the returned block with zeros. The existing graph-edit transition does not bridge this parameter-triggered warm-up.

**Required work:** Keep an audible dry/previous path while the pitch processor warms up, then make a controlled transition. Verify initial activation, changing from zero, and reactivation. This is separate from the previously deferred reduction of the 4,096-frame playback reservoir.

**Limit:** Once warmed up, the tested single-pitch runs had no extended silent gaps. The observed problem is the activation transition, not evidence of continuous instability in one active Pitch node.

## 210-04 — Preset nodes become clipped when the window is narrowed

**Reproduction:** Load the bundled **Skanda's Brighten** preset. Compare the wider window with the narrower one, using the window's zoom action. This was repeated after loading the saved preset again, outside a tutorial.

**Expected:** All effects remain reachable when the window changes size, without changing the audible chain order.

**Actual:** In the narrower tested window, Clarity is mostly beyond the right canvas edge. Widening the window reveals the full node; narrowing it clips the same node again. The name, body, and controls are partly offscreen. The canvas does not provide a horizontal scroll or Fit action to bring that node back into view.

**Evidence:** [narrow after reloading](docs/release-2.1.0-evidence/ui-brighten-reloaded.png), [wide window](docs/release-2.1.0-evidence/ui-zoomed-canvas.png), [narrow repeat](docs/release-2.1.0-evidence/ui-narrow-canvas-repeat.png). Captured images are 891×768 and 1,224×768 respectively; those are screenshot dimensions, not a claim about macOS logical display scaling.

**Location:** Brighten stores Clarity at approximately x=861.55 in `Sonexis/StarterPresets.json`. `CanvasView.nodePosition` uses a nonzero stored position directly. `updateCanvasSizeIfNeeded` updates the canvas size without adjusting viewport reachability. Drag/drop clamping does not address an already-loaded node when the canvas shrinks.

**Required work:** Make existing nodes reachable through appropriate viewport fitting/panning or a comparable minimal solution. Avoid silently reordering Automatic chains or rewriting their saved positions as a side effect of resizing.

## 210-05 — Gain sliders lack accessible names and units

**Reproduction:** Outside a tutorial, open the gear settings and inspect the accessibility tree.

**Expected:** The sliders identify themselves as **Input Gain** and **Output Gain**, with values such as **−15 dB** and **+15 dB**.

**Actual:** The controls are exposed as `slider Value: -15` and `slider Value: 15`, without names or units. Their visible labels appear together in a separate text element: `Input Gain -15 dB Output Gain +15 dB Ceiling`. They are not associated with the individual slider elements.

**Evidence:** [actual settings accessibility tree](docs/release-2.1.0-evidence/ui-settings.txt) and [matching screenshot](docs/release-2.1.0-evidence/ui-settings.png). `AudioSettingsInspectorSlider` in `HeaderView.swift` constructs an unlabeled Slider beneath a separate HStack of Text views.

**Required work:** Give each slider an explicit accessible label and a dB-formatted accessible value. Verify the names/values after doing so, including equal numeric values where the two sliders cannot be distinguished by their numbers.

**Limit:** This finding concerns the observed accessibility properties. A complete VoiceOver or Full Keyboard Access session was not performed, and this report does not claim that every control is inaccessible.

## 210-06 — App Chains tutorial locks Power while leaving it off

**Reproduction:** With processing stopped, go to Home → Tutorial → App chains & menu bar. Add an app chain and proceed to the effect/preset and enable/disable instructions.

**Expected:** The learner has a way to start processing and audition the app-specific effects during the interactive lesson.

**Actual:** Processing remains stopped. The header Power button is disabled with the help text **Power is controlled by this tutorial**. The menu bar Power control is also disabled for an active tutorial, and `ChainWorkspace.togglePower` rejects calls during the app-chain steps. The lesson can be advanced, but neither Power control can start audio in this state.

**Evidence:** [intro state](docs/release-2.1.0-evidence/ui-app-chains-intro.txt), [practice chain added](docs/release-2.1.0-evidence/ui-practice-app-added.txt), and [preset instruction](docs/release-2.1.0-evidence/ui-app-preset-step.txt). `beginAppTutorial` snapshots the prior running state without starting processing; HeaderView locks Power outside `buildPower`; ChainMenuBarPanel disables its Power button during any active tutorial.

**Required work:** Provide a deliberate way to start audio in this lesson, or include a start step before auditioning effects. Retain restoration of the user's original running/stopped state on exit.

**Limit:** This occurs when the lesson starts with processing stopped. It is not evidence that the lesson stops already-running audio or that its chain add/remove operations fail.

## Working through these findings

Start with 210-01 and 210-02, then 210-03. Implement one fix at a time, retain the existing behavior elsewhere, and append the tested revision and before/after evidence to each resolved entry. The [release roadmap](docs/RELEASE-2.1.0-ROADMAP.md) remains the shipping checklist.
